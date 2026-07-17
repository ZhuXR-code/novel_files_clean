package com.filescanner.app.data.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * 一次扫描对应一个“文库”。每次启动扫描都新建一条 ScanRunEntity，
 * 本次扫到的所有文件都以 scan_run_id 关联回它；文库列表按这些记录展示，
 * 进入某文库只读取该次扫描的文件（而非全部文件混在一起）。
 */
@Entity(tableName = "scan_run")
data class ScanRunEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val name: String = "",
    @ColumnInfo(name = "folder_uri")
    val folderUri: String = "",
    @ColumnInfo(name = "folder_name")
    val folderName: String = "",
    @ColumnInfo(name = "file_types")
    val fileTypes: String = "txt",
    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),
    @ColumnInfo(name = "file_count")
    val fileCount: Int = 0
)
