package com.filescanner.app.data.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * 扫描配置（对应 PC 网页版左侧“扫描配置”列表 + “新增”弹窗）。
 * 一条配置保存：名称、扫描根目录 URI、文件类型、最小体积、是否递归、
 * 是否精确内容去重、需要排除的子文件夹名称。
 *
 * folderUri 保存 SAF 树 URI 字符串（已通过 takePersistableUriPermission 持久化权限）；
 * folderName 保存可阅读的路径名，仅用于界面反显，不参与扫描。
 */
@Entity(tableName = "scan_config")
data class ScanConfigEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    @ColumnInfo(name = "name")
    val name: String = "",
    @ColumnInfo(name = "folder_uri")
    val folderUri: String,
    @ColumnInfo(name = "folder_name")
    val folderName: String = "",
    @ColumnInfo(name = "file_types")
    val fileTypes: String = "txt",
    @ColumnInfo(name = "min_size_kb")
    val minSizeKb: Int = 0,
    @ColumnInfo(name = "recursive")
    val recursive: Boolean = true,
    @ColumnInfo(name = "exact_hash")
    val exactHash: Boolean = false,
    @ColumnInfo(name = "excluded_folders")
    val excludedFolders: String = "",
    /** "quick"=快速扫描(不检测编码), "deep"=深度扫描(检测编码)。默认 quick。 */
    @ColumnInfo(name = "scan_mode", defaultValue = "'quick'")
    val scanMode: String = "quick"
)
