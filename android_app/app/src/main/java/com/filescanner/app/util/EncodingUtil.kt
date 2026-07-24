package com.filescanner.app.util

import android.content.Context
import android.net.Uri
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.io.InputStream
import java.nio.charset.Charset
import kotlin.math.min

/**
 * 文件编码探测工具。
 *
 * 探测规则：
 * 1. 先检查 BOM（UTF-8、UTF-16LE、UTF-16BE）；
 * 2. 无 BOM 时严格校验 UTF-8；
 * 3. 不合法则按中文 txt 最常见的 GB18030（GBK 超集）兜底。
 *
 * 支持 content://、file:// 以及绝对文件路径。
 */
object EncodingUtil {

    private const val DEFAULT_SAMPLE_BYTES = 8 * 1024

    /**
     * 探测文件编码并返回编码显示名称（如 "UTF-8"、"GB18030"）。
     */
    fun detectEncodingName(
        context: Context,
        path: String,
        sampleBytes: Int = DEFAULT_SAMPLE_BYTES
    ): String {
        return detectEncodingAndBom(context, path, sampleBytes).first.displayName()
    }

    /**
     * 探测文件编码并返回 (Charset, 需跳过的 BOM 字节数)。
     */
    fun detectEncodingAndBom(
        context: Context,
        path: String,
        sampleBytes: Int = DEFAULT_SAMPLE_BYTES
    ): Pair<Charset, Long> {
        val sample = ByteArray(sampleBytes)
        var sampleLen = 0
        openRawStream(context, path).use { ins ->
            while (sampleLen < sampleBytes) {
                val n = ins.read(sample, sampleLen, sampleBytes - sampleLen)
                if (n <= 0) break
                sampleLen += n
            }
        }
        return detectCharset(sample, sampleLen)
    }

    private fun openRawStream(context: Context, path: String): InputStream {
        return when {
            path.startsWith("content://") -> {
                context.contentResolver.openInputStream(Uri.parse(path))
                    ?: throw IOException("无法打开输入流（文件可能已被移动或删除）：$path")
            }
            path.startsWith("file://") -> FileInputStream(File(path.removePrefix("file://")))
            else -> FileInputStream(File(path))
        }
    }

    /**
     * 根据采样字节返回 (编码, 需跳过的 BOM 字节数)。
     */
    private fun detectCharset(sample: ByteArray, len: Int): Pair<Charset, Long> {
        if (len >= 3 &&
            sample[0] == 0xEF.toByte() && sample[1] == 0xBB.toByte() && sample[2] == 0xBF.toByte()
        ) return Charsets.UTF_8 to 3L
        if (len >= 2 && sample[0] == 0xFF.toByte() && sample[1] == 0xFE.toByte()) {
            return charset("UTF-16LE") to 2L
        }
        if (len >= 2 && sample[0] == 0xFE.toByte() && sample[1] == 0xFF.toByte()) {
            return charset("UTF-16BE") to 2L
        }
        return if (looksLikeUtf8(sample, len)) Charsets.UTF_8 to 0L
        else charset("GB18030") to 0L
    }

    /**
     * 手写 UTF-8 合法性校验；采样末尾被截断的多字节序列不算错误。
     */
    private fun looksLikeUtf8(b: ByteArray, len: Int): Boolean {
        val actualLen = min(len, b.size)
        var i = 0
        while (i < actualLen) {
            val c = b[i].toInt() and 0xFF
            val need = when {
                c < 0x80 -> 0
                c in 0xC2..0xDF -> 1
                c in 0xE0..0xEF -> 2
                c in 0xF0..0xF4 -> 3
                else -> return false
            }
            if (i + need >= actualLen) return true
            for (j in 1..need) {
                if ((b[i + j].toInt() and 0xC0) != 0x80) return false
            }
            i += need + 1
        }
        return true
    }
}
