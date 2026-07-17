package com.filescanner.app.data.model

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.atomic.AtomicLong

/**
 * 单条删除日志（real-time 滚动展示）。
 * [seq] 单调递增，作为 LazyColumn 的稳定唯一 key，避免同名文件撞键导致崩溃。
 */
data class DeleteLogLine(val text: String, val ok: Boolean, val seq: Long = 0)

/**
 * 删除过程状态。由 DeleteService 更新，DeleteProgressScreen 实时观察。
 * [logLines] 保留最近 1000 条日志，屏幕打开后即可看到历史明细。
 */
data class DeleteState(
    val isDeleting: Boolean = false,
    val done: Int = 0,
    val total: Int = 0,
    val success: Int = 0,
    val failed: Int = 0,
    val finished: Boolean = false
)

object DeleteStateManager {
    private const val MAX_LOG = 1000
    private val seqCounter = AtomicLong(0)

    private val _state = MutableStateFlow(DeleteState())
    val state: StateFlow<DeleteState> = _state.asStateFlow()

    // 内部可变缓冲：逐条 append，仅在节流时拷贝快照发出，避免 10w 级删除时每次 log 都全量拷贝列表
    private val _logBuffer = mutableListOf<DeleteLogLine>()
    private val _logLines = MutableStateFlow<List<DeleteLogLine>>(emptyList())
    val logLines: StateFlow<List<DeleteLogLine>> = _logLines.asStateFlow()

    fun update(s: DeleteState) {
        _state.value = s
    }

    /** 追加一条日志（仅内部缓冲，O(1)，不触发 Flow 发射）。 */
    fun log(line: String, ok: Boolean) {
        _logBuffer.add(DeleteLogLine(line, ok, seqCounter.incrementAndGet()))
        if (_logBuffer.size > MAX_LOG) _logBuffer.removeAt(0)
    }

    /** 把内部缓冲快照发出（由 DeleteService 在节流节奏下调用）。 */
    fun flushLogs() {
        _logLines.value = _logBuffer.toList()
    }

    fun reset() {
        _state.value = DeleteState()
        _logBuffer.clear()
        _logLines.value = emptyList()
    }
}
