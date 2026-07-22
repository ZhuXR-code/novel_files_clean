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
    /**
     * MediaStore 能可靠索引的“媒体类型”扩展名。
     * 分区存储（Android 10+）下，MediaStore 只完整覆盖 图片/视频/音频；
     * txt/md/pdf/epub/doc/docx 等“非媒体文件”若由文件管理器或电脑拷入（非本 App 创建），
     * MediaStore 往往查不到或只返回部分，且不抛异常——这正是内部存储“伪权限/静默空/漏扫”的根源。
     * 因此仅当目标类型全部属于媒体类型时才启用 MediaStore 快路径，其余一律走可靠的 SAF。
     */
    private val MEDIA_EXTENSIONS = setOf(
        "jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "heif", "dng", "svg",
        "mp4", "mkv", "avi", "mov", "wmv", "flv", "3gp", "webm", "m4v", "ts",
        "mp3", "wav", "flac", "aac", "ogg", "m4a", "wma", "amr", "opus"
    )

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
        // MediaStore 快路径：仅当【所有目标类型都是媒体类型(图片/视频/音频)】且是 primary 卷时启用。
        // 原因：分区存储下 MediaStore 对 txt/md/pdf 等“非媒体文件”查不全（华为/荣耀/OPPO/vivo/小米上
        // 表现为静默返回空或部分结果 → 漏扫/“未找到匹配文件”），而本 App 已通过 SAF 树权限拿到该目录的
        // 完整读权限，SAF 才是所有卷、所有 ROM、所有文件类型都可靠的正解。故非纯媒体扫描直接走 SAF。
        val allMedia = typeSet.all { it in MEDIA_EXTENSIONS }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && allMedia) {
            val fast = collectViaMediaStore(context, folderUri, recursive, minSize, typeSet, excludeSet, onFound)
            if (fast != null && fast.isNotEmpty()) return fast
            LogUtil.i("FileUtil", "MediaStore fast-path unavailable/empty, fallback to SAF")
        }

        // 主力路径：SAF DocumentsContract children 批量查询 + 多线程并行遍历。
        // 每个目录只 1 次 IPC 取回全部子项，并用线程池并发处理多个目录，
        // 让 SAF 跨进程 IPC 的阻塞等待相互重叠，10w 级文件从单线程数十秒进一步降到数秒级。
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

        // 线程安全的收集容器与计数
        val results = java.util.concurrent.ConcurrentLinkedQueue<FileEntry>()
        val foundCount = java.util.concurrent.atomic.AtomicInteger(0)
        val dirCount = java.util.concurrent.atomic.AtomicInteger(0)
        val stopped = java.util.concurrent.atomic.AtomicBoolean(false)
        // 未完成任务数（含已提交未执行 + 执行中）；归零即遍历结束
        val pending = java.util.concurrent.atomic.AtomicInteger(0)
        val doneLock = Object()

        // SAF 每次 children 查询都是跨进程 IPC 阻塞调用，用线程池并发多目录以重叠等待。
        val nThreads = Runtime.getRuntime().availableProcessors().coerceIn(4, 8)
        val executor = java.util.concurrent.Executors.newFixedThreadPool(nThreads)

        // 处理单个目录：查询其直接子项，命中文件入队、子目录再提交任务
        lateinit var submit: (String) -> Unit
        val processDir: (String) -> Unit = processDir@{ parentDocId ->
            if (stopped.get()) return@processDir
            if (shouldStop?.invoke() == true) { stopped.set(true); return@processDir }
            val myIndex = dirCount.incrementAndGet()
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId)
            try {
                cr.query(childrenUri, projection, null, null, null)?.use { cur ->
                    if (myIndex == 1) {
                        LogUtil.i("FileUtil", "root children count=${cur.count} uri=$childrenUri")
                    }
                    val idCol = cur.getColumnIndexOrThrow(colId)
                    val nameCol = cur.getColumnIndexOrThrow(colName)
                    val sizeCol = cur.getColumnIndexOrThrow(colSize)
                    val mimeCol = cur.getColumnIndexOrThrow(colMime)
                    while (cur.moveToNext()) {
                        if (stopped.get()) break
                        val docId = cur.getString(idCol) ?: continue
                        val name = cur.getString(nameCol) ?: continue
                        val mime = cur.getString(mimeCol) ?: ""
                        val isDir = mime == mimeDir
                        if (isDir) {
                            // 排除列表按目录名匹配：命中的子文件夹整体跳过
                            if (excludeSet.isNotEmpty() && name in excludeSet) continue
                            if (recursive) submit(docId)
                        } else {
                            val len = if (cur.isNull(sizeCol)) 0L else cur.getLong(sizeCol)
                            if (isSupportedFile(name, typeSet) && len >= minSize) {
                                val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                                results.add(FileEntry(name, docUri, len))
                                val n = foundCount.incrementAndGet()
                                // 节流上报进度，避免 10w 次回调压垮 UI
                                if (n % 64 == 0) onFound?.invoke(n)
                            }
                        }
                    }
                } ?: LogUtil.e("FileUtil", "children query null for $parentDocId uri=$childrenUri")
            } catch (e: Exception) {
                LogUtil.e("FileUtil", "DocContract children query failed for $parentDocId: ${e.message}")
            }
        }

        submit = { docId ->
            pending.incrementAndGet()
            executor.execute {
                try {
                    processDir(docId)
                } finally {
                    if (pending.decrementAndGet() == 0) {
                        synchronized(doneLock) { doneLock.notifyAll() }
                    }
                }
            }
        }

        submit(rootDocId)
        // 等待所有目录任务完成（wait 带超时轮询，兜底防丢失 notify）
        synchronized(doneLock) {
            while (pending.get() > 0) {
                try {
                    doneLock.wait(200)
                } catch (e: InterruptedException) {
                    stopped.set(true)
                    Thread.currentThread().interrupt()
                    break
                }
            }
        }
        executor.shutdown()
        try {
            executor.awaitTermination(5, java.util.concurrent.TimeUnit.SECONDS)
        } catch (e: InterruptedException) {
            executor.shutdownNow()
        }
        // 收尾补报一次最终数量
        onFound?.invoke(foundCount.get())
        LogUtil.i("FileUtil", "DocContract(parallel x$nThreads) traversed ${dirCount.get()} dirs, ${results.size} files")
        return results.toList()
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
