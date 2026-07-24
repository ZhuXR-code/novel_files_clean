package com.filescanner.app.data.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.filescanner.app.data.database.entity.DupRuleConfigEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface DupRuleConfigDao {

    /** 取全部规则配置（内置排前，自定义按 sortOrder 排序）。 */
    @Query("SELECT * FROM dup_rule_configs ORDER BY is_builtin DESC, sort_order ASC, id ASC")
    fun getAll(): Flow<List<DupRuleConfigEntity>>

    /** 取全部已启用内置规则的 ruleKey 集合。 */
    @Query("SELECT rule_key FROM dup_rule_configs WHERE enabled = 1 AND is_builtin = 1")
    suspend fun getEnabledBuiltinRuleKeys(): List<String>

    /** 取全部已启用的用户自定义规则。 */
    @Query("SELECT * FROM dup_rule_configs WHERE enabled = 1 AND is_builtin = 0 AND conditions IS NOT NULL")
    suspend fun getEnabledUserRules(): List<DupRuleConfigEntity>

    /** 按 rule_key 查单条。 */
    @Query("SELECT * FROM dup_rule_configs WHERE rule_key = :ruleKey LIMIT 1")
    suspend fun getByKey(ruleKey: String): DupRuleConfigEntity?

    /** 按 id 查单条。 */
    @Query("SELECT * FROM dup_rule_configs WHERE id = :id LIMIT 1")
    suspend fun getById(id: Long): DupRuleConfigEntity?

    /** 插入（冲突时替换）。 */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(rule: DupRuleConfigEntity)

    /** 插入用户自定义规则，返回自增 id。 */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertUserRule(rule: DupRuleConfigEntity): Long

    /** 更新自定义规则的名称/描述/条件/动作。 */
    @Query("""
        UPDATE dup_rule_configs 
        SET rule_name = :ruleName, description = :description, 
            conditions = :conditions, action = :action, 
            updated_at = :updatedAt 
        WHERE id = :id AND is_builtin = 0
    """)
    suspend fun updateUserRule(id: Long, ruleName: String, description: String,
                               conditions: String?, action: String?,
                               updatedAt: Long = System.currentTimeMillis())

    /** 删除用户自定义规则（内置规则不删除）。 */
    @Query("DELETE FROM dup_rule_configs WHERE id = :id AND is_builtin = 0")
    suspend fun deleteUserRule(id: Long): Int

    /** 批量更新规则 enabled 状态。 */
    @Query("UPDATE dup_rule_configs SET enabled = :enabled, updated_at = :updatedAt WHERE rule_key = :ruleKey")
    suspend fun setEnabled(ruleKey: String, enabled: Boolean, updatedAt: Long = System.currentTimeMillis())

    /** 批量更新规则 enabled 状态（按 id）。 */
    @Query("UPDATE dup_rule_configs SET enabled = :enabled, updated_at = :updatedAt WHERE id = :id")
    suspend fun setEnabledById(id: Long, enabled: Boolean, updatedAt: Long = System.currentTimeMillis())

    /** 按 rule_key 幂等插入默认规则（若不存在）。 */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertIfNotExists(rule: DupRuleConfigEntity)

    /** 判断某 rule_key 是否存在。 */
    @Query("SELECT COUNT(*) FROM dup_rule_configs WHERE rule_key = :ruleKey")
    suspend fun countByKey(ruleKey: String): Int

    /** 获取当前最大 sort_order（用于新规则排序）。 */
    @Query("SELECT COALESCE(MAX(sort_order), 0) FROM dup_rule_configs")
    suspend fun getMaxSortOrder(): Int

    /** 取全部规则（非 Flow 版本，用于种子初始化）。 */
    @Query("SELECT * FROM dup_rule_configs ORDER BY id ASC")
    suspend fun getAllSync(): List<DupRuleConfigEntity>
}
