package com.filescanner.app.data.model

import androidx.room.ColumnInfo

/**
 * 合集分组头（按书名 title 聚合的统计结果，非数据库实体）。
 * 由 RawQuery 的 GROUP BY 查询映射得到，用于合集模式列表展示。
 * title 为空表示“未解析”合集。
 */
data class NovelGroup(
    @ColumnInfo(name = "group_title") val title: String,
    @ColumnInfo(name = "file_count") val fileCount: Int,
    @ColumnInfo(name = "total_size") val totalSize: Long
)
