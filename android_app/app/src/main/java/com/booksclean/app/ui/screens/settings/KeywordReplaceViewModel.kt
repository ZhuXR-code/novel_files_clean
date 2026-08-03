package com.booksclean.app.ui.screens.settings

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.booksclean.app.FileScannerApp
import com.booksclean.app.data.database.entity.KeywordReplaceRuleEntity
import com.booksclean.app.util.KeywordReplace
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class KeywordReplaceViewModel(application: Application) : AndroidViewModel(application) {
    private val app = application as FileScannerApp
    private val repo = app.repository

    val scanRules: StateFlow<List<KeywordReplaceRuleEntity>> =
        repo.getRulesFlow(KeywordReplace.SCOPE_SCAN)
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    val parseRules: StateFlow<List<KeywordReplaceRuleEntity>> =
        repo.getRulesFlow(KeywordReplace.SCOPE_PARSE)
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun upsert(rule: KeywordReplaceRuleEntity) =
        viewModelScope.launch(Dispatchers.IO) { repo.upsertRule(rule) }

    fun delete(rule: KeywordReplaceRuleEntity) =
        viewModelScope.launch(Dispatchers.IO) { repo.deleteRule(rule) }

    fun setEnabled(id: Long, enabled: Boolean) =
        viewModelScope.launch(Dispatchers.IO) { repo.setRuleEnabled(id, enabled) }

    /**
     * 批量启用 / 不启用：ids 由页面传入（当前搜索过滤后可见的规则）。
     * 直接写数据库，返回上一页再进入状态依旧保留。
     */
    fun setEnabledBatch(ids: List<Long>, enabled: Boolean, onDone: (Int) -> Unit = {}) =
        viewModelScope.launch(Dispatchers.IO) {
            repo.setRulesEnabled(ids, enabled)
            launch(Dispatchers.Main) { onDone(ids.size) }
        }

    /** 新规则默认追加到该作用域末尾（sort_order = 当前最大 + 1）。 */
    suspend fun nextSortOrder(scope: String): Int = repo.maxRuleSortOrder(scope) + 1

    /**
     * 批量新增：mode = "remove"（每行一个关键词，作删除替换）或 "replace"（每行 "AAA||B"，AAA→B）。
     * 解析后逐条追加到该作用域末尾，刷新即生效。
     */
    fun batchAdd(scope: String, mode: String, text: String, enabled: Boolean, onDone: () -> Unit = {}) =
        viewModelScope.launch(Dispatchers.IO) {
            val lines = text.lines().map { it.trim() }.filter { it.isNotEmpty() }
            var order = repo.maxRuleSortOrder(scope)
            for (line in lines) {
                val (pattern, replacement) = if (mode == "replace") {
                    val idx = line.indexOf("||")
                    line.substring(0, idx).trim() to line.substring(idx + 2).trim()
                } else {
                    line to ""
                }
                if (pattern.isEmpty()) continue
                repo.upsertRule(
                    KeywordReplaceRuleEntity(
                        scope = scope,
                        pattern = pattern,
                        replacement = replacement,
                        sortOrder = ++order,
                        enabled = enabled
                    )
                )
            }
            launch(Dispatchers.Main) { onDone() }
        }
}
