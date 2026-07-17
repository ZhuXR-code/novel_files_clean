package com.filescanner.app.util

import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 轻量内存日志 + 可选落盘。不依赖加密，便于本地排查问题。
 */
object LogUtil {
    private const val MAX_LOG_LINES = 1000
    private val logs = mutableListOf<String>()
    private val dateFormat = SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.getDefault())
    private const val TAG = "FileScanner"

    @Synchronized
    private fun write(level: String, tag: String, message: String) {
        val line = "[${dateFormat.format(Date())}] [$level/$tag] $message"
        synchronized(logs) {
            logs.add(line)
            if (logs.size > MAX_LOG_LINES) logs.removeAt(0)
        }
        when (level) {
            "E" -> android.util.Log.e(TAG, "[$tag] $message")
            "W" -> android.util.Log.w(TAG, "[$tag] $message")
            "D" -> android.util.Log.d(TAG, "[$tag] $message")
            else -> android.util.Log.i(TAG, "[$tag] $message")
        }
    }

    fun d(tag: String, message: String) = write("D", tag, message)
    fun i(tag: String, message: String) = write("I", tag, message)
    fun w(tag: String, message: String) = write("W", tag, message)
    fun e(tag: String, message: String) = write("E", tag, message)

    @Synchronized
    fun getLogText(): String = synchronized(logs) { logs.joinToString("\n") }

    @Synchronized
    fun clear() = synchronized(logs) { logs.clear() }
}
