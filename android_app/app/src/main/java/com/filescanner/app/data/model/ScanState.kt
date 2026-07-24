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

/**
 * 最近一次“开始扫描”所使用的配置参数。
 * 供扫描进度页在“停止/完成后”提供“重新扫描”按钮，复用同一文件夹与参数重新发起扫描。
 */
data class LastScanConfig(
    val treeUri: String,
    val fileTypes: String,
    val minSizeKb: Int,
    val recursive: Boolean,
    val excludedFolders: String,
    val configName: String,
    val folderName: String,
    val scanMode: String = "quick"
)

object ScanStateManager {
    private val _state = MutableStateFlow(ScanState())
    val state: StateFlow<ScanState> = _state.asStateFlow()

    /**
     * 进程内"停止扫描"请求标志。
     * UI（界面按钮 / 通知栏按钮）点击停止时直接置位，扫描协程在循环中检测后自行退出。
     * 之所以不依赖 startService(STOP) 跨组件通信，是因为 Android 8.0+ 的后台启动限制
     * 常导致 stop 命令意图无法送达，出现"点了停止却没停"的问题。
     */
    private val _stopRequested = MutableStateFlow(false)
    val stopRequested: StateFlow<Boolean> = _stopRequested.asStateFlow()
    fun requestStop() {
        _stopRequested.value = true
    }

    /**
     * 当前（或最近一次）扫描对应的文库 runId。
     * 供“一键清理”等编排流程在扫描完成后读取，以便对本次文库执行
     * 勾选重复 / 删除等操作。与扫描进度状态分开保存，避免被 ScanState 的
     * 多次 update() 覆盖清零。
     */
    private val _runId = MutableStateFlow(0L)
    val runId: StateFlow<Long> = _runId.asStateFlow()
    fun setRunId(id: Long) {
        _runId.value = id
    }

    /**
     * 最近一次扫描的配置参数（文件夹/类型/排除项等），供“重新扫描”按钮复用。
     * 不随 reset() 清空，确保停止后仍能按原参数重扫。
     */
    private val _lastConfig = MutableStateFlow<LastScanConfig?>(null)
    val lastConfig: StateFlow<LastScanConfig?> = _lastConfig.asStateFlow()
    fun setLastConfig(c: LastScanConfig) {
        _lastConfig.value = c
    }

    fun update(s: ScanState) {
        _state.value = s
    }

    fun reset() {
        _state.value = ScanState()
        _stopRequested.value = false
        _runId.value = 0L
    }
}
