package com.filescanner.app.data.database.entity

import androidx.room.ColumnInfo

/**
 * 复刻 PC 端"勾选重复"逻辑所需的轻量投影：
 * id / 文件名(fileName) / 书名(title) / 作者(author) / 进度(progress) / 来源(source) / 大小(fileSize) / 创建时间(createdAt)。
 */
data class DuplicateRow(
    val id: Long,
    @ColumnInfo(name = "fileName") val fileName: String,
    val title: String,
    val author: String,
    val progress: String,
    @ColumnInfo(name = "source") val source: String = "",
    @ColumnInfo(name = "fileSize") val fileSize: Long,
    @ColumnInfo(name = "createdAt") val createdAt: Long
)
