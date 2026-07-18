package com.filescanner.app.service

import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.net.Uri
import android.os.IBinder
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.isActive

import com.filescanner.app.FileScannerApp
import com.filescanner.app.MainActivity
import com.filescanner.app.R
import com.filescanner.app.data.database.entity.ScannedFileEntity
import com.filescanner.app.data.model.ScanState
import com.filescanner.app.data.model.LastScanConfig
import com.filescanner.app.data.model.ScanStateManager
import com.filescanner.app.util.FileUtil
import com.filescanner.app.util.KeywordReplace
import com.filescanner.app.util.LogUtil
import com.filescanner.app.util.Parser
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicLong

class ScanService : Service() {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var scanJob: Job? = null

    private val lastNotificationTime = AtomicLong(0)
    private val NOTIFICATION_THROTTLE_MS = 1500L
    private val STATE_THROTTLE_MS = 200L

    private val app by lazy { application as FileScannerApp }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_START_SCAN) {
            val treeUriStr = intent.getStringExtra("tree_uri") ?: return START_NOT_STICKY
            val treeUri = Uri.parse(treeUriStr)
            val fileTypes = intent.getStringExtra("file_types") ?: "txt"
            val minSizeKb = intent.getIntExtra("min_size_kb", 0)
            val recursive = intent.getBooleanExtra("recursive", true)
            // 需要排除的子文件夹名称（逗号分隔）
            val excludedFolders = intent.getStringExtra("excluded_folders") ?: ""
            // 文库（本次扫描）名称与展示用文件夹名
            val configName = intent.getStringExtra("config_name") ?: ""
            val folderName = intent.getStringExtra("folder_name") ?: ""
            LogUtil.i("ScanService", "startScan tree=$treeUri types=$fileTypes recursive=$recursive exclude=$excludedFolders")

            // 记录本次扫描配置，供进度页“重新扫描”按钮复用
            ScanStateManager.setLastConfig(
                LastScanConfig(
                    treeUri = treeUriStr,
                    fileTypes = fileTypes,
                    minSizeKb = minSizeKb,
                    recursive = recursive,
                    excludedFolders = excludedFolders,
                    configName = configName,
                    folderName = folderName
                )
            )

            startForeground(NOTIFICATION_ID, createNotification(getString(R.string.scan_preparing)))
            startScanning(treeUri, fileTypes, minSizeKb, recursive, excludedFolders, configName, folderName)
        } else if (intent?.action == ACTION_STOP_SCAN) {
            stopScanning()
        }
        return START_NOT_STICKY
    }

    private fun startScanning(
        treeUri: Uri,
        fileTypes: String,
        minSizeKb: Int,
        recursive: Boolean,
        excludedFolders: String,
        configName: String,
        folderName: String
    ) {
        ScanStateManager.reset()
        scanJob = serviceScope.launch {
            // 本次扫描对应一个文库（scan_run）：进入扫描前先建记录，拿到 runId 关联文件
            val runName = configName.ifBlank { folderName.ifBlank { "文库" } }
            val runId = app.repository.createScanRun(runName, treeUri.toString(), folderName, fileTypes)
            // 记录本次文库 runId，供“一键清理”等编排流程在扫描完成后使用
            ScanStateManager.setRunId(runId)
            try {
                // 收集阶段：实时上报“已收集 N 个文件”，避免大目录遍历时界面一直停在 0。
                var lastCollectUpdate = 0L
                ScanStateManager.update(ScanState(isScanning = true, phase = "collecting"))
                val fileList = FileUtil.collectSupportedFiles(
                    app, treeUri, recursive, minSizeKb, fileTypes, excludedFolders,
                    shouldStop = { ScanStateManager.stopRequested.value }
                ) { collected ->
                    val now = System.currentTimeMillis()
                    if (now - lastCollectUpdate >= STATE_THROTTLE_MS) {
                        lastCollectUpdate = now
                        ScanStateManager.update(
                            ScanState(isScanning = true, phase = "collecting", collectedFiles = collected)
                        )
                    }
                }
                val total = fileList.size
                LogUtil.i("ScanService", "Collected $total files for run=$runId")

                // 加载关键词替换规则（对齐 PC 端）：扫描阶段作用于文件名，解析阶段作用于解析结果。
                // 一次性载入后循环内复用，避免每条文件重复查库。
                val scanRules = app.repository.getEnabledRules(KeywordReplace.SCOPE_SCAN)
                val parseRules = app.repository.getEnabledRules(KeywordReplace.SCOPE_PARSE)
                // 循环外预判断：规则为空则跳过替换，省去每条文件的无效调用（性能）
                val hasScanRules = scanRules.isNotEmpty()
                val hasParseRules = parseRules.isNotEmpty()

                if (total == 0) {
                    app.repository.setRunFileCount(runId, 0)
                    ScanStateManager.update(
                        ScanState(isScanning = false, totalFiles = 0, finished = true,
                            status = "empty")
                    )
                    updateNotificationNow(getString(R.string.scan_no_files))
                    stopSelf()
                    return@launch
                }

                ScanStateManager.update(ScanState(isScanning = true, phase = "scanning", totalFiles = total))

                var done = 0
                val buffer = mutableListOf<ScannedFileEntity>()
                // 进度 StateFlow 节流：每 200ms 最多发射一次（通知本身也节流），
                // 避免 10w 级文件时每文件都新建对象并触发 UI 重组合
                var lastState = System.currentTimeMillis()
                var stopped = false
                for (entry in fileList) {
                    // 检测取消（协程被 cancel）或进程内停止请求标志，二者任一即退出
                    if (!isActive || ScanStateManager.stopRequested.value) {
                        stopped = true
                        break
                    }
                    // 1) 扫描阶段规则：先清洗文件名（与 PC scan_rules 作用于 file_name 一致）
                    val rawName = entry.name
                    val fileName = if (hasScanRules) (KeywordReplace.applyRules(rawName, scanRules) ?: rawName) else rawName
                    // 2) 解析文件名得到 书名/作者/进度/来源
                    val parsed = Parser.parseFileName(fileName)
                    // 3) 解析阶段规则：清洗解析结果（与 PC parse_rules 作用于 书名/作者/进度/来源 一致）
                    val title = if (hasParseRules) (KeywordReplace.applyRules(parsed.title, parseRules) ?: parsed.title) else parsed.title
                    val author = if (hasParseRules) (KeywordReplace.applyRules(parsed.author, parseRules) ?: parsed.author) else parsed.author
                    val progress = if (hasParseRules) (KeywordReplace.applyRules(parsed.progress, parseRules) ?: parsed.progress) else parsed.progress
                    val source = if (hasParseRules) (KeywordReplace.applyRules(parsed.source, parseRules) ?: parsed.source) else parsed.source
                    val hash = ""
                    val ext = FileUtil.getFileExtension(fileName)
                    buffer.add(
                        ScannedFileEntity(
                            path = entry.uri.toString(),
                            fileName = fileName,
                            fileSize = entry.size,
                            title = title,
                            author = author,
                            progress = progress,
                            source = source,
                            contentHash = hash,
                            ext = ext,
                            scanRunId = runId
                        )
                    )
                    done++
                    val now = System.currentTimeMillis()
                    if (now - lastState >= STATE_THROTTLE_MS || done == total) {
                        lastState = now
                        val progress = (done * 100) / total
                        ScanStateManager.update(
                            ScanState(
                                isScanning = true, phase = "scanning", progress = progress,
                                scannedFiles = done, totalFiles = total, currentFile = fileName
                            )
                        )
                    }
                    updateNotificationThrottled(
                        getString(R.string.scanning_file, fileName, done, total)
                    )
                    // 批量写库，减少事务次数（每 50 条落一次）
                    if (buffer.size >= 50) {
                        app.repository.insertAll(buffer.toList())
                        buffer.clear()
                    }
                }
                if (stopped) {
                    // 停止：保留已写入库的文件，flush 最后一批不足 50 条的记录
                    if (buffer.isNotEmpty()) {
                        app.repository.insertAll(buffer.toList())
                        buffer.clear()
                    }
                    ScanStateManager.update(
                        ScanState(
                            isScanning = false, phase = "scanning",
                            progress = if (total > 0) (done * 100) / total else 0,
                            scannedFiles = done, totalFiles = total,
                            finished = true, status = "stopped"
                        )
                    )
                    updateNotificationNow(getString(R.string.scan_stopped, done))
                    LogUtil.i("ScanService", "Scan stopped by user at $done/$total (run=$runId)")
                } else {
                    if (buffer.isNotEmpty()) {
                        app.repository.insertAll(buffer.toList())
                        buffer.clear()
                    }
                    ScanStateManager.update(
                        ScanState(
                            isScanning = false, phase = "scanning", progress = 100, scannedFiles = total,
                            totalFiles = total, finished = true, status = "completed"
                        )
                    )
                    app.repository.setRunFileCount(runId, total)
                    updateNotificationNow(getString(R.string.scan_completed, total))
                    LogUtil.i("ScanService", "Scan finished: $total files (run=$runId)")
                }
            } catch (e: CancellationException) {
                LogUtil.i("ScanService", "Scan cancelled")
            } catch (e: Exception) {
                LogUtil.e("ScanService", "Scan failed: ${e.message}")
                ScanStateManager.update(
                    ScanState(isScanning = false, error = e.message ?: "", finished = true,
                        status = "error")
                )
                updateNotificationNow("${getString(R.string.scan_error)}: ${e.message}")
            } finally {
                stopSelf()
            }
        }
    }

    private fun stopScanning() {
        // 置位进程内停止标志，确保协程（即便因后台限制未收到 stop 命令）也能在下一检查点退出
        ScanStateManager.requestStop()
        scanJob?.cancel()
        scanJob = null
        val s = ScanStateManager.state.value
        ScanStateManager.update(
            s.copy(isScanning = false, finished = true, status = "stopped")
        )
        updateNotificationNow(getString(R.string.scan_stopped, s.scannedFiles))
        stopSelf()
    }

    private fun updateNotificationThrottled(text: String) {
        val now = System.currentTimeMillis()
        if (now - lastNotificationTime.get() >= NOTIFICATION_THROTTLE_MS) {
            lastNotificationTime.set(now)
            updateNotificationNow(text)
        }
    }

    private fun createNotification(text: String) = NotificationCompat.Builder(this, FileScannerApp.SCAN_CHANNEL_ID)
        .setContentTitle(getString(R.string.scan_notification_title))
        .setContentText(text)
        .setSmallIcon(android.R.drawable.ic_menu_search)
        .setPriority(NotificationCompat.PRIORITY_LOW)
        .setOngoing(true)
        .setContentIntent(
            PendingIntent.getActivity(
                this, 0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        )
        .addAction(
            android.R.drawable.ic_media_pause,
            getString(R.string.stop_scan),
            PendingIntent.getBroadcast(
                this, 1,
                Intent(this, StopScanReceiver::class.java).apply { action = ACTION_STOP_SCAN },
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        )
        .build()

    private fun updateNotificationNow(text: String) {
        try {
            val manager = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
            manager.notify(NOTIFICATION_ID, createNotification(text))
        } catch (e: Exception) {
            LogUtil.e("ScanService", "updateNotification failed: ${e.message}")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        scanJob?.cancel()
        serviceScope.cancel()
        LogUtil.i("ScanService", "ScanService destroyed")
    }

    companion object {
        const val ACTION_START_SCAN = "com.filescanner.app.START_SCAN"
        const val ACTION_STOP_SCAN = "com.filescanner.app.STOP_SCAN"
        private const val NOTIFICATION_ID = 1
    }
}
