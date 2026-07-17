package com.filescanner.app.data.database.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.filescanner.app.data.database.entity.KeywordReplaceRuleEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface KeywordReplaceDao {
    /** 某作用域全部规则（含禁用），按 sort_order、id 升序，供界面展示与编辑。 */
    @Query("SELECT * FROM keyword_replace_rules WHERE scope = :scope ORDER BY sort_order ASC, id ASC")
    fun getByScopeFlow(scope: String): Flow<List<KeywordReplaceRuleEntity>>

    /** 某作用域已启用规则，按 sort_order、id 升序，供扫描/解析时应用（对齐 PC load_rules）。 */
    @Query("SELECT * FROM keyword_replace_rules WHERE scope = :scope AND enabled = 1 ORDER BY sort_order ASC, id ASC")
    suspend fun getEnabledByScope(scope: String): List<KeywordReplaceRuleEntity>

    /** REPLACE：新建（id=0）插入，编辑（带原 id）则替换。 */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(rule: KeywordReplaceRuleEntity)

    @Query("DELETE FROM keyword_replace_rules WHERE id = :id")
    suspend fun deleteById(id: Long)

    @Query("UPDATE keyword_replace_rules SET enabled = :enabled WHERE id = :id")
    suspend fun setEnabled(id: Long, enabled: Boolean)

    /** 某作用域当前最大 sort_order，新规则默认追加到末尾。 */
    @Query("SELECT COALESCE(MAX(sort_order), 0) FROM keyword_replace_rules WHERE scope = :scope")
    suspend fun maxSortOrder(scope: String): Int
}
