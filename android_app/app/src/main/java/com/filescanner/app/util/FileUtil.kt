package com.filescanner.app.util

import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.annotation.RequiresApi
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
        /** 返回 true 时立即停止收集（用于“停止扫描”）。每次迭代都会检查，开销极小。 */
        shouldStop: (() -> Boolean)? = null,
        onFound: ((collected: Int) -> Unit)? = null
    ): List<FileEntry> {
        val typeSet = fileTypes.split(",").map { it.trim().lowercase() }
            .filter { it.isNotEmpty() }.toSet()
        if (typeSet.isEmpty()) return emptyList()
        val minSize = minSizeKb * 1024L
        val excludeSet = excludedFolders.split(",").map { it.trim() }
            .filter { it.isNotEmpty() }.toSet()
        // 优先用 MediaStore 一次性查询（仅 primary 卷、API 29+），避免 DocumentFile 逐文件 IPC 遍历，
        // 10w 级文件从数十分钟降到秒级。非 primary 卷 / 低版本 / 查询异常时回退 SAF 递归。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val fast = collectViaMediaStore(context, folderUri, recursive, minSize, typeSet, excludeSet, onFound)
            if (fast != null) return fast
        }

        // SAF 卷（含 MuMuShared 等非 primary 卷）走 DocumentsContract children 批量查询，
        // 每目录 1 次 IPC 取回全部子项，把“每文件多次 IPC”降为“每目录 1 次 IPC”。
        val t0 = System.currentTimeMillis()
        val results = collectViaDocContract(context, folderUri, recursive, minSize, typeSet, excludeSet, shouldStop, onFound)
        LogUtil.i("FileUtil", "DocContract collect done: ${results.size} files in ${System.currentTimeMillis() - t0} ms")
        return results
    }

    /**
     * 通过 DocumentsContract 的 children 批量查询递归收集文件。
     *
     * 相比 DocumentFile.listFiles()（每个文件属性都会触发一次跨进程 IPC），
     * 这里每个目录只走 1 次 query 即可取回该目录下所有文件的
     * document_id / display_name / _size / mime_type / flags，
     * 把“每文件多次 IPC”降为“每目录一次 IPC”，在 SAF 框架下（含 MuMuShared 等非 primary 卷）
     * 也能把 10w 级文件从数十分钟降到几十秒。用栈式遍历避免深目录递归爆栈。
     */
    private fun collectViaDocContract(
        context: Context,
        treeUri: Uri,
        recursive: Boolean,
        minSize: Long,
        typeSet: Set<String>,
        excludeSet: Set<String>,
        shouldStop: (() -> Boolean)?,
        onFound: ((collected: Int) -> Unit)?
    ): List<FileEntry> {
        val results = mutableListOf<FileEntry>()
        val cr = context.contentResolver
        // 注意：SAF DocumentsContract 的显示名列是 "_display_name"（带下划线），不是 "display_name"
        val colId = DocumentsContract.Document.COLUMN_DOCUMENT_ID
        val colName = DocumentsContract.Document.COLUMN_DISPLAY_NAME
        val colSize = DocumentsContract.Document.COLUMN_SIZE
        val colMime = DocumentsContract.Document.COLUMN_MIME_TYPE
        val colFlags = DocumentsContract.Document.COLUMN_FLAGS
        val projection = arrayOf(colId, colName, colSize, colMime, colFlags)
        val mimeDir = DocumentsContract.Document.MIME_TYPE_DIR
        val rootDocId = DocumentsContract.getTreeDocumentId(treeUri)
        LogUtil.i("FileUtil", "rootDocId=$rootDocId treeUri=$treeUri")
        val stack = java.util.ArrayDeque<String>()
        stack.addLast(rootDocId)
        var dirCount = 0
        while (stack.isNotEmpty()) {
            if (shouldStop?.invoke() == true) break
            val parentDocId = stack.removeLast()
            dirCount++
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId)
            try {
                val c = cr.query(childrenUri, projection, null, null, null)
                if (c == null) {
                    LogUtil.e("FileUtil", "children query null for $parentDocId uri=$childrenUri")
                    continue
                }
                c.use { cur ->
                    if (dirCount == 1) {
                        LogUtil.i("FileUtil", "root children count=${cur.count} uri=$childrenUri")
                    }
                    val idCol = cur.getColumnIndexOrThrow(colId)
                    val nameCol = cur.getColumnIndexOrThrow(colName)
                    val sizeCol = cur.getColumnIndexOrThrow(colSize)
                    val mimeCol = cur.getColumnIndexOrThrow(colMime)
                    var firstLogged = false
                    while (cur.moveToNext()) {
                        val docId = cur.getString(idCol)
                        val name = cur.getString(nameCol) ?: continue
                        val mime = cur.getString(mimeCol) ?: ""
                        if (dirCount == 1 && !firstLogged) {
                            LogUtil.i("FileUtil", "first child: docId=$docId name=$name mime=$mime")
                            firstLogged = true
                        }
                        val isDir = mime == mimeDir
                        if (isDir) {
                            // 排除列表按目录名匹配：命中的子文件夹整体跳过
                            if (excludeSet.isNotEmpty() && name in excludeSet) continue
                            if (recursive) stack.addLast(docId)
                        } else {
                            val len = if (cur.isNull(sizeCol)) 0L else cur.getLong(sizeCol)
                            if (isSupportedFile(name, typeSet) && len >= minSize) {
                                val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                                results.add(FileEntry(name, docUri, len))
                                onFound?.invoke(results.size)
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                LogUtil.e("FileUtil", "DocContract children query failed for $parentDocId: ${e.message}")
            }
        }
        LogUtil.i("FileUtil", "DocContract traversed $dirCount dirs")
        return results
    }

    /**
     * 通过 MediaStore 一次性查询某棵树目录下（含子目录）的所有匹配文件。
     *
     * 相比 DocumentFile 逐文件跨进程 IPC 遍历，这里只走 1 条 query，10w 级文件可秒级返回。
     * 仅支持 primary（内部存储）卷；其他情况返回 null，由调用方回退到 SAF 递归。
     * 注意：返回的 uri 仍构造回 SAF 文档 URI（buildDocumentUriUsingTree），保证后续删除逻辑不变。
     */
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun collectViaMediaStore(
        context: Context,
        folderUri: Uri,
        recursive: Boolean,
        minSize: Long,
        typeSet: Set<String>,
        excludeSet: Set<String>,
        onFound: ((collected: Int) -> Unit)?
    ): List<FileEntry>? {
        val root = parseTreeRoot(folderUri) ?: return null
        val volumeId = root.first
        if (volumeId != "primary") return null
        val mediaVolume = MediaStore.VOLUME_EXTERNAL_PRIMARY

        val projection = arrayOf(
            "_id",
            "_display_name",
            "_size",
            "relative_path"
        )
        val base = if (root.second.isEmpty()) "" else root.second + "/"
        val (selection, selArgs) = if (recursive) {
            if (base.isEmpty()) {
                null to emptyArray()
            } else {
                // 精确匹配本目录或任意子目录，避免 "novels" 误匹配 "novels2/"
                "( relative_path = ? OR relative_path LIKE ? )" to
                    arrayOf(base, base + "%")
            }
        } else {
            "relative_path = ?" to arrayOf(base)
        }

        val results = mutableListOf<FileEntry>()
        try {
            val uri = MediaStore.Files.getContentUri(mediaVolume)
            context.contentResolver.query(uri, projection, selection, selArgs, null)?.use { c ->
                val idCol = c.getColumnIndexOrThrow("_id")
                val nameCol = c.getColumnIndexOrThrow("_display_name")
                val sizeCol = c.getColumnIndexOrThrow("_size")
                val relCol = c.getColumnIndexOrThrow("relative_path")
                while (c.moveToNext()) {
                    val name = c.getString(nameCol) ?: continue
                    if (!isSupportedFile(name, typeSet)) continue
                    val rel = c.getString(relCol) ?: ""
                    if (excludeSet.isNotEmpty()) {
                        val segs = rel.split('/').filter { it.isNotEmpty() }
                        if (segs.any { it in excludeSet }) continue
                    }
                    val len = if (c.isNull(sizeCol)) 0L else c.getLong(sizeCol)
                    if (len < minSize) continue
                    val docId = "$volumeId:$rel$name"
                    val docUri = DocumentsContract.buildDocumentUriUsingTree(folderUri, docId)
                    results.add(FileEntry(name, docUri, len))
                    onFound?.invoke(results.size)
                }
            }
        } catch (e: Exception) {
            LogUtil.e("FileUtil", "MediaStore collect failed, fallback to SAF: ${e.message}")
            return null
        }
        LogUtil.i("FileUtil", "MediaStore collect done: ${results.size} files (primary volume)")
        return results
    }

    /** 解析 SAF 树 URI，返回 (卷ID, 相对路径)，如 ("primary", "Download/novels")。解析失败返回 null。 */
    private fun parseTreeRoot(uri: Uri): Pair<String, String>? {
        val path = uri.path ?: return null
        val seg = path.substringAfter("tree/")
        if (seg.isBlank()) return null
        val decoded = Uri.decode(seg)
        val idx = decoded.indexOf(':')
        if (idx < 0) return null
        val volume = decoded.substring(0, idx)
        val relative = decoded.substring(idx + 1)
        return volume to relative
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
