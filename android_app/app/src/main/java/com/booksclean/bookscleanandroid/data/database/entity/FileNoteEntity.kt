package com.bookscleanandroid.app.data.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * 文件备注实体：每个扫描文件可有多条备注（一个文件多条、条数不限）。
 * - content：备注内容，限 50 字以内，同一 fileId 内内容去重（区分大小写）。
 * - 主键 id 自增；fileId + content 唯一约束（区分大小写由建表 COLLATE 决定，见 DAO 说明）。
 */
@Entity(
    tableName = "file_notes",
    indices = [
        Index(value = ["file_id"]),
        Index(value = ["file_id", "content"], unique = true)
    ]
)
data class FileNoteEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,

    @ColumnInfo(name = "file_id")
    val fileId: Long,

    @ColumnInfo(name = "content")
    val content: String,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis()
)
