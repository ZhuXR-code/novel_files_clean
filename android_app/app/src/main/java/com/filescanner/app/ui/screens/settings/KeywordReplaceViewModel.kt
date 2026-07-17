package com.filescanner.app.ui.screens.settings

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.filescanner.app.FileScannerApp
import com.filescanner.app.data.database.entity.KeywordReplaceRuleEntity
import com.filescanner.app.util.KeywordReplace
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

    /** 新规则默认追加到该作用域末尾（sort_order = 当前最大 + 1）。 */
    suspend fun nextSortOrder(scope: String): Int = repo.maxRuleSortOrder(scope) + 1
}
