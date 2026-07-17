package com.filescanner.app.data.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * 关键词替换规则（对齐 PC 端 keyword_replace_rules 表）。
 *
 * scope: "scan" = 扫描阶段作用于文件名(file_name)；
 *        "parse" = 解析阶段作用于 书名/作者/进度/来源。
 * pattern: 被替换的关键词/字符串。
 * replacement: 替换后内容，空串表示删除。
 * sort_order: 同作用域内执行顺序（小靠前）。
 * enabled: 是否启用。
 */
@Entity(tableName = "keyword_replace_rules")
data class KeywordReplaceRuleEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val scope: String = "scan",
    val pattern: String = "",
    @ColumnInfo(name = "replacement")
    val replacement: String = "",
    @ColumnInfo(name = "sort_order")
    val sortOrder: Int = 0,
    @ColumnInfo(name = "enabled")
    val enabled: Boolean = true,
    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis()
)
