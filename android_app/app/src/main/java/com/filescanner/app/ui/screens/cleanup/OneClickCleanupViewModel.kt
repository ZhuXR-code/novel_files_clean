package com.filescanner.app.ui.screens.cleanup

import android.content.Context
import android.content.Intent
import android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION
import android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.filescanner.app.FileScannerApp
import com.filescanner.app.data.model.DeleteStateManager
import com.filescanner.app.data.model.ScanStateManager
import com.filescanner.app.service.DeleteService
import com.filescanner.app.service.ScanService
import com.filescanner.app.data.database.entity.ScannedFileEntity
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * 一键清理：对齐电脑端“一键清理”流程（扫描 → 勾选重复 → 删除）。
 *
 * 阶段（phase）：
 *  - idle    ：未开始，选择文件夹
 *  - scanning：扫描中（复用 ScanService，观察 ScanStateManager）
 *  - marking ：扫描完成，正在计算重复文件
 *  - confirm ：已算出重复文件，等待用户确认删除
 *  - deleting：删除中（复用 DeleteService，观察 DeleteStateManager）
 *  - done    ：完成
 *  - error   ：出错
 */
class OneClickCleanupViewModel(application: android.app.Application) :
    AndroidViewModel(application) {

    val scanState = ScanStateManager.state
    val deleteState = DeleteStateManager.state
    val deleteLogs = DeleteStateManager.logLines

    private val _phase = MutableStateFlow("idle")
    val phase: StateFlow<String> = _phase.asStateFlow()

    private val _folderName = MutableStateFlow("")
    val folderName: StateFlow<String> = _folderName.asStateFlow()

    private val _scanned = MutableStateFlow(0)
    val scanned: StateFlow<Int> = _scanned.asStateFlow()

    private val _duplicateCount = MutableStateFlow(0)
    val duplicateCount: StateFlow<Int> = _duplicateCount.asStateFlow()

    private val _error = MutableStateFlow("")
    val error: StateFlow<String> = _error.asStateFlow()

    private var scanStarted = false
    private var scanHandled = false
    private var deleteHandled = false
    private var pendingIds: List<Long> = emptyList()
    // 用户在“清单”页勾选的待删除集合（默认全选，可取消部分）；确认删除时以此为准
    private val _selectedIds = MutableStateFlow<Set<Long>>(emptySet())
    val selectedIds: StateFlow<Set<Long>> = _selectedIds.asStateFlow()
    // 清单页展示的文件实体列表
    private val _reviewItems = MutableStateFlow<List<ScannedFileEntity>>(emptyList())
    val reviewItems: StateFlow<List<ScannedFileEntity>> = _reviewItems.asStateFlow()
    // 清单页草稿勾选集合（review 期间实时维护，返回/保存时落地到 selectedIds）
    private val _draftIds = MutableStateFlow<Set<Long>>(emptySet())
    val draftIds: StateFlow<Set<Long>> = _draftIds.asStateFlow()

    fun startCleanup(
        context: Context,
        treeUri: Uri,
        folderName: String,
        fileTypes: String
    ) {
        if (scanStarted) return
        scanStarted = true
        scanHandled = false
        deleteHandled = false
        pendingIds = emptyList()
        _folderName.value = folderName
        _scanned.value = 0
        _duplicateCount.value = 0
        _error.value = ""

        // 先重置扫描状态，避免复用上一次扫描的 finished 标志造成误触发
        ScanStateManager.reset()

        // 持久化 URI 权限，确保后续删除服务能通过存储的文档 URI 删除文件
        try {
            context.contentResolver.takePersistableUriPermission(
                treeUri,
                FLAG_GRANT_READ_URI_PERMISSION or FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (_: Exception) {
        }

        _phase.value = "scanning"
        val intent = Intent(context, ScanService::class.java).apply {
            action = ScanService.ACTION_START_SCAN
            putExtra("tree_uri", treeUri.toString())
            putExtra("file_types", if (fileTypes.isBlank()) "txt" else fileTypes)
            putExtra("min_size_kb", 0)
            putExtra("recursive", true)
            putExtra("excluded_folders", "")
            putExtra("config_name", "$folderName·一键清理")
            putExtra("folder_name", folderName)
        }
        context.startForegroundService(intent)
    }

    /** 扫描完成后由界面调用：读取本次文库，计算重复文件，进入确认页（展示数量/清单，用户确认后删除） */
    fun onScanFinished() {
        if (scanHandled) return
        scanHandled = true
        val runId = ScanStateManager.runId.value
        if (runId <= 0) {
            _error.value = "未获取到扫描文库，无法继续"
            _phase.value = "error"
            return
        }
        _scanned.value = ScanStateManager.state.value.scannedFiles
        viewModelScope.launch {
            _phase.value = "marking"
            val ids = repository().selectDuplicateIds(runId)
            _duplicateCount.value = ids.size
            if (ids.isEmpty()) {
                _phase.value = "done"
                return@launch
            }
            pendingIds = ids
            _selectedIds.value = ids.toSet()
            _phase.value = "confirm"
        }
    }

    fun confirmDelete() {
        val ids = _selectedIds.value.toList()
        if (ids.isEmpty()) {
            _phase.value = "done"
            return
        }
        DeleteStateManager.reset()
        deleteHandled = false
        _phase.value = "deleting"
        val ctx = getApplication<FileScannerApp>()
        val intent = Intent(ctx, DeleteService::class.java).apply {
            action = DeleteService.ACTION_START_DELETE
            putExtra("ids", ids.toLongArray())
        }
        ctx.startForegroundService(intent)
    }

    /** 打开“将要删除的文件清单”页，供用户取消勾选不想删除的文件 */
    fun openReview() {
        viewModelScope.launch {
            _draftIds.value = _selectedIds.value
            _reviewItems.value = repository().getByIds(pendingIds)
            _phase.value = "review"
        }
    }

    /** 保存清单勾选结果并回到确认页（selectedIds 即为最终待删除集合） */
    fun saveReview() {
        _selectedIds.value = _draftIds.value
        _phase.value = "confirm"
    }

    /** 返回确认页：同样应用清单草稿，使确认页数量与用户在清单中的勾选一致 */
    fun backToConfirm() {
        _selectedIds.value = _draftIds.value
        _phase.value = "confirm"
    }

    /** 清单页勾选实时切换（草稿） */
    fun toggleDraft(id: Long) {
        _draftIds.value = if (id in _draftIds.value) _draftIds.value - id else _draftIds.value + id
    }

    /** 清单页批量设置草稿勾选（全选 / 取消全选） */
    fun updateDraft(ids: Set<Long>) {
        _draftIds.value = ids
    }

    fun cancelCleanup() {
        _phase.value = "done"
    }

    /** 删除完成后由界面调用 */
    fun onDeleteFinished() {
        if (deleteHandled) return
        deleteHandled = true
        _phase.value = "done"
    }

    private fun repository() = getApplication<FileScannerApp>().repository
}
