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
import com.filescanner.app.data.model.DeleteState
import com.filescanner.app.data.model.DeleteStateManager
import com.filescanner.app.util.FileUtil
import com.filescanner.app.util.FormatUtil
import com.filescanner.app.util.LogUtil
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicLong

class DeleteService : Service() {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var deleteJob: Job? = null
    /** 是否同时删除源文件：true=删除记录+源文件（旧默认）；false=仅删除记录、保留源文件。 */
    private var deleteSource: Boolean = true

    private val lastNotificationTime = AtomicLong(0)
    private val NOTIFICATION_THROTTLE_MS = 1500L

    private val app by lazy { application as FileScannerApp }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_START_DELETE) {
            val ids = intent.getLongArrayExtra("ids")?.toList() ?: run {
                stopSelf()
                return START_NOT_STICKY
            }
            // 是否同时删除源文件：批量删除选中弹窗会显式传入；缺省 true 沿用旧行为（连源文件一起删）
            deleteSource = intent.getBooleanExtra("deleteSource", true)
            startForeground(NOTIFICATION_ID, createNotification(getString(R.string.deleting)))
            startDeleting(ids)
        }
        return START_NOT_STICKY
    }

    private fun startDeleting(ids: List<Long>) {
        DeleteStateManager.reset()
        deleteJob = serviceScope.launch {
            try {
                val total = ids.size
                LogUtil.i("DeleteService", "[操作] 开始删除：共 $total 个文件（${if (deleteSource) "删除记录+源文件" else "仅删除记录"}）")
                if (total == 0) {
                    DeleteStateManager.update(DeleteState(finished = true, total = 0))
                    stopSelf()
                    return@launch
                }
                var success = 0
                var failed = 0
                var processed = 0
                // 受影响的文库 id 集合：删除成功后需重算其文件数，使文库列表的 fileCount 与实际一致
                val affectedRuns = mutableSetOf<Long>()
                // 分批加载实体并删除，避免一次性 SELECT * 全部实体导致 OOM（上万文件时）
                val batchSize = 200
                for (batchStart in ids.indices step batchSize) {
                    if (!isActive) break
                    val batchEnd = minOf(batchStart + batchSize, ids.size)
                    val entities = app.repository.getByIds(ids.subList(batchStart, batchEnd))
                    val successIds = mutableListOf<Long>()
                    for (f in entities) {
                        if (!isActive) break
                        if (deleteSource) {
                            // 删除记录 + 源文件：物理删除成功才删记录
                            val ok = FileUtil.deleteViaUri(app, Uri.parse(f.path))
                            if (ok) {
                                successIds.add(f.id)
                                affectedRuns.add(f.scanRunId)
                                success++
                                DeleteStateManager.log("✓ ${f.fileName}（${FormatUtil.formatSize(f.fileSize)}）", true)
                            } else {
                                failed++
                                DeleteStateManager.log("✗ ${f.fileName} —— 删除失败（可能已被移动或权限不足）", false)
                            }
                        } else {
                            // 仅删除记录：不碰源文件，直接删库
                            successIds.add(f.id)
                            affectedRuns.add(f.scanRunId)
                            success++
                            DeleteStateManager.log("✓ ${f.fileName}（仅删除记录，保留源文件）", true)
                        }
                        processed++
                    }
                    // 每批立即删除已成功的记录，释放内存
                    if (successIds.isNotEmpty()) {
                        app.repository.deleteByIds(successIds)
                    }
                    val now = System.currentTimeMillis()
                    if (now - lastNotificationTime.get() >= NOTIFICATION_THROTTLE_MS) {
                        lastNotificationTime.set(now)
                        DeleteStateManager.update(
                            DeleteState(isDeleting = true, done = processed,
                                total = total, success = success, failed = failed)
                        )
                        DeleteStateManager.flushLogs()
                        updateNotificationNow("已处理 $processed/$total（成功 $success，失败 $failed）")
                    }
                }
                // 删除完成后，重算所有受影响文库的文件数（回写 scan_run.file_count），
                // 否则文库列表（外部文库列表）仍显示删除前的旧文件数。
                if (affectedRuns.isNotEmpty()) {
                    val t0 = System.currentTimeMillis()
                    affectedRuns.forEach { app.repository.recomputeRunFileCount(it) }
                    LogUtil.i("DeleteService", "重算 ${affectedRuns.size} 个文库文件数，耗时 ${System.currentTimeMillis() - t0}ms")
                }
                DeleteStateManager.update(
                    DeleteState(isDeleting = false, done = processed, total = total,
                        success = success, failed = failed, finished = true)
                )
                DeleteStateManager.flushLogs()
                LogUtil.i("DeleteService", "[操作] 删除完成：共 $total 个，成功 $success，失败 $failed")
            } catch (e: CancellationException) {
                LogUtil.i("DeleteService", "Delete cancelled")
            } catch (e: Exception) {
                LogUtil.e("DeleteService", "Delete failed: ${e.message}")
            } finally {
                stopSelf()
            }
        }
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
        .setSmallIcon(android.R.drawable.ic_menu_delete)
        .setPriority(NotificationCompat.PRIORITY_LOW)
        .setOngoing(true)
        .setContentIntent(
            PendingIntent.getActivity(
                this, 0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        )
        .build()

    private fun updateNotificationNow(text: String) {
        try {
            val manager = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
            manager.notify(NOTIFICATION_ID, createNotification(text))
        } catch (e: Exception) {
            LogUtil.e("DeleteService", "updateNotification failed: ${e.message}")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        deleteJob?.cancel()
        serviceScope.cancel()
        LogUtil.i("DeleteService", "DeleteService destroyed")
    }

    companion object {
        const val ACTION_START_DELETE = "com.filescanner.app.START_DELETE"
        private const val NOTIFICATION_ID = 2
    }
}
