package com.filescanner.app.util

import android.net.Uri

object FormatUtil {
    fun formatSize(bytes: Long): String = when {
        bytes < 1024 -> "$bytes B"
        bytes < 1024 * 1024 -> String.format("%.1f KB", bytes / 1024.0)
        bytes < 1024 * 1024 * 1024 -> String.format("%.1f MB", bytes / (1024.0 * 1024.0))
        else -> String.format("%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0))
    }

    /**
     * 把 SAF content:// URI 或本地路径转成更易读的形式，仅用于页面展示。
     * 不改变底层存储：DB 中仍是原始 URI，打开文件时也仍用原始路径。
     *
     * - 解码 %2F / %20 / %3A 等 URL 编码（让中文文件名、空格显示正常）；
     * - 优先取 SAF document id（/document/ 之后）作为文件真实相对路径；
     * - 去掉存储卷标识（primary: / MuMuShared: 等），只保留人类可读的目录与文件名。
     */
    fun toHumanReadablePath(raw: String): String {
        if (raw.isBlank()) return raw
        val decoded = Uri.decode(raw)
        val docPart = Regex("/document/(.*)$").find(decoded)?.groupValues?.get(1) ?: decoded
        return docPart.replace(Regex("^[A-Za-z0-9]+:"), "")
    }
}
