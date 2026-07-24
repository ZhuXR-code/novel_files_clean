package com.filescanner.app.data.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "scanned_file",
    indices = [
        Index(value = ["path", "scan_run_id"], unique = true),
        Index("marked"),
        Index("checked"),
        Index("title"),
        Index("scan_run_id")
    ]
)
data class ScannedFileEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val path: String,
    @ColumnInfo(name = "file_name")
    val fileName: String,
    @ColumnInfo(name = "file_size")
    val fileSize: Long = 0,
    val title: String = "",
    val author: String = "",
    @ColumnInfo(name = "progress", defaultValue = "''")
    val progress: String = "",
    @ColumnInfo(name = "source", defaultValue = "''")
    val source: String = "",
    @ColumnInfo(name = "encoding", defaultValue = "''")
    val encoding: String = "",
    @ColumnInfo(name = "title_pinyin", defaultValue = "''")
    val titlePinyin: String = "",
    @ColumnInfo(name = "author_pinyin", defaultValue = "''")
    val authorPinyin: String = "",
    @ColumnInfo(name = "content_hash")
    val contentHash: String = "",
    val ext: String = "",
    @ColumnInfo(name = "marked")
    val marked: Int = 0,
    @ColumnInfo(name = "checked")
    val checked: Int = 0,
    @ColumnInfo(name = "scan_run_id")
    val scanRunId: Long = 0,
    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),
    /** 文件在文件系统中的最后修改时间（毫秒时间戳）。扫描时从 file.lastModified() 读取。 */
    @ColumnInfo(name = "file_date")
    val fileDate: Long? = null
)
