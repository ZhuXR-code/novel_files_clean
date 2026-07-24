package com.filescanner.app.data.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * 勾选重复规则配置实体。
 * 内置规则（isBuiltin=true）不可删除；用户自定义规则（isBuiltin=false）可增删改。
 * 自定义规则使用 conditions（JSON）+ action 模式。
 */
@Entity(tableName = "dup_rule_configs")
data class DupRuleConfigEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,

    @ColumnInfo(name = "rule_key")
    val ruleKey: String,

    @ColumnInfo(name = "rule_name")
    val ruleName: String,

    val enabled: Boolean = true,

    val description: String = "",

    /** 是否为内置规则（内置规则不可删除，有 -1 的 sortOrder） */
    @ColumnInfo(name = "is_builtin", defaultValue = "0")
    val isBuiltin: Boolean = false,

    /** 自定义规则的条件 JSON：[{"field":"file_name","regex":"水印"}]，多条为「且」关系。兼容旧格式 op+value。 */
    val conditions: String? = null,

    /** 自定义规则的动作: "check"（勾选）或 "protect"（保护） */
    val action: String? = null,

    /** 自定义规则的执行顺序（升序） */
    @ColumnInfo(name = "sort_order", defaultValue = "0")
    val sortOrder: Int = 0,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "updated_at")
    val updatedAt: Long = System.currentTimeMillis(),
)
