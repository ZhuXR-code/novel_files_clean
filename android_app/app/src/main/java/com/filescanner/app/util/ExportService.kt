package com.filescanner.app.util

import android.content.Context
import com.filescanner.app.data.database.entity.ScannedFileEntity
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import java.io.File

/**
 * 将已标记文件清单导出为 JSON，保存到应用私有外部目录 /Android/data/<pkg>/files/exports/。
 */
object ExportService {
    private val gson: Gson = GsonBuilder().setPrettyPrinting().create()

    fun writeMarked(context: Context, files: List<ScannedFileEntity>): String? {
        if (files.isEmpty()) return null
        val dir = File(context.getExternalFilesDir(null), "exports")
        if (!dir.exists()) dir.mkdirs()
        val file = File(dir, "marked_files_${System.currentTimeMillis()}.json")
        val items = files.map {
            mapOf(
                "fileName" to it.fileName,
                "path" to it.path,
                "title" to it.title,
                "author" to it.author,
                "source" to it.source,
                "progress" to it.progress,
                "size" to it.fileSize
            )
        }
        val payload = mapOf("count" to items.size, "files" to items)
        file.writeText(gson.toJson(payload))
        LogUtil.i("Export", "Exported ${items.size} files to ${file.absolutePath}")
        return file.absolutePath
    }
}
