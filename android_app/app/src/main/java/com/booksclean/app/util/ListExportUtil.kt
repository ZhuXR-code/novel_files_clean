package com.booksclean.app.util

import com.booksclean.app.data.database.entity.ScannedFileEntity
import com.booksclean.app.data.model.NovelGroup
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 书库列表 / 合集列表「导出为 TXT」的列定义与内容生成。
 *
 * 导出格式：一行一本（或一个合集），各列之间用制表符 \t 分隔，首行为表头。
 * 单元格内出现的 \t / 换行会被替换成空格，避免破坏列对齐。
 */
object ListExportUtil {

    /** 列表模式可导出的列。[key] 用于持久化勾选状态，[label] 为表头与弹框显示名。 */
    enum class FileColumn(val key: String, val label: String) {
        TITLE("title", "小说名"),
        AUTHOR("author", "作者"),
        PROGRESS("progress", "进度"),
        SOURCE("source", "来源"),
        FILE_NAME("file_name", "文件名"),
        FILE_SIZE("file_size", "文件大小"),
        FILE_PATH("file_path", "文件路径"),
        ENCODING("encoding", "编码"),
        EXT("ext", "扩展名"),
        FILE_DATE("file_date", "文件修改时间"),
        CREATED_AT("created_at", "入库时间"),
        MARKED("marked", "标记状态"),
        CHECKED("checked", "勾选状态")
    }

    /** 合集模式可导出的列。 */
    enum class GroupColumn(val key: String, val label: String) {
        TITLE("title", "小说名"),
        FILE_COUNT("file_count", "文件数"),
        TOTAL_SIZE("total_size", "总大小"),
        CHECKED_COUNT("checked_count", "已勾选数")
    }

    /** 默认勾选：仅「小说名」。 */
    val DEFAULT_FILE_COLUMNS = setOf(FileColumn.TITLE.key)
    val DEFAULT_GROUP_COLUMNS = setOf(GroupColumn.TITLE.key)

    private const val SEP = "\t"
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())

    /** 清洗单元格：制表符/换行替换为空格，避免撑乱列。 */
    private fun cell(value: String?): String {
        if (value.isNullOrEmpty()) return ""
        return value.replace('\t', ' ').replace('\r', ' ').replace('\n', ' ')
    }

    private fun fileCellValue(file: ScannedFileEntity, column: FileColumn): String = when (column) {
        FileColumn.TITLE -> file.title
        FileColumn.AUTHOR -> file.author
        FileColumn.PROGRESS -> file.progress
        FileColumn.SOURCE -> file.source
        FileColumn.FILE_NAME -> file.fileName
        FileColumn.FILE_SIZE -> FormatUtil.formatSize(file.fileSize)
        FileColumn.FILE_PATH -> file.path
        FileColumn.ENCODING -> file.encoding
        FileColumn.EXT -> file.ext
        FileColumn.FILE_DATE -> file.fileDate?.takeIf { it > 0 }?.let { dateFormat.format(Date(it)) } ?: ""
        FileColumn.CREATED_AT -> if (file.createdAt > 0) dateFormat.format(Date(file.createdAt)) else ""
        FileColumn.MARKED -> if (file.marked == 1) "已标记" else "未标记"
        FileColumn.CHECKED -> if (file.checked == 1) "已勾选" else "未勾选"
    }

    private fun groupCellValue(group: NovelGroup, column: GroupColumn): String = when (column) {
        GroupColumn.TITLE -> group.title.ifEmpty { "未解析" }
        GroupColumn.FILE_COUNT -> group.fileCount.toString()
        GroupColumn.TOTAL_SIZE -> FormatUtil.formatSize(group.totalSize)
        GroupColumn.CHECKED_COUNT -> group.checkedCount.toString()
    }

    /**
     * 生成列表模式的 TXT 内容。[selectedKeys] 为用户勾选的列 key；
     * 输出列顺序固定按 [FileColumn] 声明顺序，不随用户点击顺序变化。
     */
    fun buildFilesText(files: List<ScannedFileEntity>, selectedKeys: Set<String>): String {
        val columns = FileColumn.entries.filter { it.key in selectedKeys }
        if (columns.isEmpty()) return ""
        return buildString {
            append(columns.joinToString(SEP) { it.label })
            append('\n')
            files.forEach { file ->
                append(columns.joinToString(SEP) { cell(fileCellValue(file, it)) })
                append('\n')
            }
        }
    }

    /** 生成合集模式的 TXT 内容。 */
    fun buildGroupsText(groups: List<NovelGroup>, selectedKeys: Set<String>): String {
        val columns = GroupColumn.entries.filter { it.key in selectedKeys }
        if (columns.isEmpty()) return ""
        return buildString {
            append(columns.joinToString(SEP) { it.label })
            append('\n')
            groups.forEach { group ->
                append(columns.joinToString(SEP) { cell(groupCellValue(group, it)) })
                append('\n')
            }
        }
    }

    /** 生成默认文件名，如 书库列表_20260802_143012.txt */
    fun buildFileName(isGroupMode: Boolean): String {
        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
        return if (isGroupMode) "合集列表_$stamp.txt" else "书库列表_$stamp.txt"
    }
}
