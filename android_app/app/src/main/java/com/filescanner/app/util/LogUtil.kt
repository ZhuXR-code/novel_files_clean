package com.filescanner.app.util

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import java.io.BufferedWriter
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * 统一日志工具：
 * - 同时写入 android.util.Log（调试日志 / logcat），便于开发期抓 logcat 排查。
 * - 内存保留最近 1000 条，供“设置→调试日志”页面查看与一键复制。
 * - 追加写入应用私有目录 debug.log（持久化，便于后续调试与导出）。
 *
 * 注意：写文件在 IO 线程执行，主线程调用安全；内存队列有锁保护。
 */
object LogUtil {
    private const val MAX_MEM = 1000
    private val mem = ArrayDeque<String>(MAX_MEM)
    private val memLock = ReentrantLock()
    private val fileLock = ReentrantLock()
    private val dateFmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)

    @Volatile private var logFile: File? = null

    /** 初始化日志文件目录（应用启动时调用一次） */
    fun init(context: Context) {
        try {
            val dir = File(context.filesDir, "logs")
            if (!dir.exists()) dir.mkdirs()
            logFile = File(dir, "debug.log")
        } catch (e: Exception) {
            logFile = null
        }
    }

    private fun now(): String = dateFmt.format(Date())

    @Synchronized
    private fun appendMem(tag: String, msg: String, level: String) {
        val line = "[${now()}] [$level/$tag] $msg"
        memLock.withLock {
            if (mem.size >= MAX_MEM) mem.removeFirst()
            mem.addLast(line)
        }
        // 异步写文件，避免阻塞调用线程
        val f = logFile
        if (f != null) {
            val toWrite = line
            Thread {
                try {
                    fileLock.withLock {
                        BufferedWriter(FileWriter(f, true)).use { it.write(toWrite + "\n") }
                    }
                } catch (_: Exception) { /* 忽略写文件失败 */ }
            }.start()
        }
    }

    fun v(tag: String, msg: String) { android.util.Log.v(tag, msg); appendMem(tag, msg, "V") }
    fun d(tag: String, msg: String) { android.util.Log.d(tag, msg); appendMem(tag, msg, "D") }
    fun i(tag: String, msg: String) { android.util.Log.i(tag, msg); appendMem(tag, msg, "I") }
    fun w(tag: String, msg: String) { android.util.Log.w(tag, msg); appendMem(tag, msg, "W") }
    fun e(tag: String, msg: String) { android.util.Log.e(tag, msg); appendMem(tag, msg, "E") }

    /** 取内存中的全部日志（时间正序），用于页面展示与一键复制 */
    fun getLogText(): String = memLock.withLock { mem.joinToString("\n") }

    /** 清空内存日志（不影响已落盘的 debug.log） */
    fun clear() { memLock.withLock { mem.clear() } }

    /** 清空持久化 debug.log（同时清空内存） */
    fun clearFile(context: Context) {
        clear()
        try { File(context.filesDir, "logs/debug.log").writeText("") } catch (_: Exception) {}
    }
}
