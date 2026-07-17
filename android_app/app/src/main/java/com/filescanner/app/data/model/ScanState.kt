package com.filescanner.app.data.model

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * 扫描过程状态。由 ScanService 更新，UI（ScanProgressScreen）通过观察 StateFlow 实时刷新。
 */
data class ScanState(
    val isScanning: Boolean = false,
    /** 阶段："collecting"（正在遍历文件树）/ "scanning"（正在解析与入库）/ "" */
    val phase: String = "",
    val progress: Int = 0,
    val scannedFiles: Int = 0,
    val totalFiles: Int = 0,
    /** 收集阶段已找到的匹配文件数（totalFiles 未知时用于实时反馈，避免界面“卡在 0”） */
    val collectedFiles: Int = 0,
    val currentFile: String = "",
    val status: String = "",
    val error: String = "",
    val finished: Boolean = false
)

object ScanStateManager {
    private val _state = MutableStateFlow(ScanState())
    val state: StateFlow<ScanState> = _state.asStateFlow()

    fun update(s: ScanState) {
        _state.value = s
    }

    fun reset() {
        _state.value = ScanState()
    }
}
