package com.filescanner.app.data.database.entity

import androidx.room.ColumnInfo

/**
 * 复刻 PC 端“标记重复”逻辑所需的轻量投影：
 * id / 书名(title) / 作者(author) / 进度(progress) / 大小(fileSize)。
 */
data class DuplicateRow(
    val id: Long,
    val title: String,
    val author: String,
    val progress: String,
    @ColumnInfo(name = "fileSize") val fileSize: Long
)
