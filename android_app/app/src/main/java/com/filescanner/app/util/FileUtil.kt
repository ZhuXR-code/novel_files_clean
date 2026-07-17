package com.filescanner.app.util

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile


/**
 * 收集阶段产出的文件条目，直接带出大小，避免后续再走一次 contentResolver 查询。
 */
data class FileEntry(val name: String, val uri: Uri, val size: Long)

object FileUtil {
    fun getFileExtension(fileName: String): String {
        val dot = fileName.lastIndexOf('.')
        return if (dot >= 0) fileName.substring(dot + 1).lowercase() else ""
    }

    fun isSupportedFile(fileName: String, types: Set<String>): Boolean {
        return getFileExtension(fileName) in types
    }

    fun getFileName(context: Context, uri: Uri): String {
        var name = "unknown.txt"
        try {
            context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val idx = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && cursor.moveToFirst()) {
                    name = cursor.getString(idx) ?: name
                }
            }
        } catch (_: Exception) {
        }
        return name
    }

    fun getFileSize(context: Context, uri: Uri): Long {
        var size = 0L
        try {
            context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val idx = cursor.getColumnIndex(android.provider.OpenableColumns.SIZE)
                if (idx >= 0 && cursor.moveToFirst()) size = cursor.getLong(idx)
            }
        } catch (_: Exception) {
        }
        return size
    }

    /**
     * 通过 SAF 树 URI 递归收集指定类型的文件，返回 (文件名, 文件URI, 大小) 列表。
     *
     * @param excludedFolders 逗号分隔的“需要排除的子文件夹名称”，匹配到目录名即跳过（不收集也不递归）。
     * @param onFound 每收集到一个匹配文件回调一次（参数为当前已收集数量），用于实时刷新 UI，
     *   避免大目录遍历期间界面一直停在 0。
     */
    fun collectSupportedFiles(
        context: Context,
        folderUri: Uri,
        recursive: Boolean,
        minSizeKb: Int,
        fileTypes: String,
        excludedFolders: String = "",
        onFound: ((collected: Int) -> Unit)? = null
    ): List<FileEntry> {
        val typeSet = fileTypes.split(",").map { it.trim().lowercase() }
            .filter { it.isNotEmpty() }.toSet()
        if (typeSet.isEmpty()) return emptyList()
        val minSize = minSizeKb * 1024L
        val excludeSet = excludedFolders.split(",").map { it.trim() }
            .filter { it.isNotEmpty() }.toSet()
        val results = mutableListOf<FileEntry>()
        val root = DocumentFile.fromTreeUri(context, folderUri) ?: return results
        collect(context, root, recursive, minSize, typeSet, excludeSet, results, onFound)
        return results
    }

    private fun collect(
        context: Context,
        doc: DocumentFile,
        recursive: Boolean,
        minSize: Long,
        typeSet: Set<String>,
        excludeSet: Set<String>,
        results: MutableList<FileEntry>,
        onFound: ((collected: Int) -> Unit)?
    ) {
        val files = doc.listFiles() ?: return
        for (file in files) {
            if (file.isDirectory) {
                // 排除列表按目录名匹配：命中的子文件夹整体跳过
                if (excludeSet.isNotEmpty() && file.name != null && file.name in excludeSet) continue
                if (recursive) collect(context, file, true, minSize, typeSet, excludeSet, results, onFound)
            } else if (file.isFile) {
                val name = file.name ?: continue
                val len = file.length()
                if (isSupportedFile(name, typeSet) && len >= minSize) {
                    results.add(FileEntry(name, file.uri, len))
                    onFound?.invoke(results.size)
                }
            }
        }
    }

    /**
     * 把 SAF 树 URI 转成可阅读的路径用于界面反显，例如：
     *   tree/primary:DCIM/Camera -> 内部存储/DCIM/Camera
     *   tree/raw:/storage/...    -> /storage/...
     */
    fun getReadableTreePath(uri: Uri): String {
        return try {
            val path = uri.path ?: return uri.toString()
            val seg = path.substringAfter("tree/")
            if (seg.isBlank()) return uri.toString()
            val decoded = Uri.decode(seg)
            when {
                decoded.startsWith("primary:") -> "内部存储/" + decoded.removePrefix("primary:")
                decoded.startsWith("raw:") -> decoded.removePrefix("raw:")
                decoded.startsWith(":") -> decoded.removePrefix(":")
                else -> decoded
            }
        } catch (_: Exception) {
            uri.toString()
        }
    }

    fun deleteViaUri(context: Context, uri: Uri): Boolean {
        return try {
            DocumentFile.fromSingleUri(context, uri)?.delete() ?: false
        } catch (e: Exception) {
            LogUtil.e("FileUtil", "deleteViaUri failed: ${e.message}")
            false
        }
    }
}
