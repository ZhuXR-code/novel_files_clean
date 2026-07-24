package com.filescanner.app.ui.screens.settings

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.filescanner.app.data.database.AppDatabase
import com.filescanner.app.data.database.dao.DupRuleConfigDao
import com.filescanner.app.data.database.entity.DupRuleConfigEntity
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class DupRuleItem(
    val id: Long = 0,
    val ruleKey: String,
    val ruleName: String,
    val enabled: Boolean,
    val description: String,
    val isBuiltin: Boolean = false,
    val conditions: String? = null,
    val action: String? = null,
)

class DupRuleConfigViewModel(application: Application) : AndroidViewModel(application) {

    private val dao: DupRuleConfigDao =
        AppDatabase.getInstance(application).dupRuleConfigDao()

    private val _rules = MutableStateFlow<List<DupRuleItem>>(emptyList())
    val rules: StateFlow<List<DupRuleItem>> = _rules.asStateFlow()

    private val _toastMsg = MutableStateFlow<String?>(null)
    val toastMsg: StateFlow<String?> = _toastMsg.asStateFlow()

    init {
        loadRules()
    }

    private fun loadRules() {
        viewModelScope.launch {
            dao.getAll().collect { entities ->
                _rules.value = entities.map { e ->
                    DupRuleItem(
                        id = e.id,
                        ruleKey = e.ruleKey,
                        ruleName = e.ruleName,
                        enabled = e.enabled,
                        description = e.description,
                        isBuiltin = e.isBuiltin,
                        conditions = e.conditions,
                        action = e.action,
                    )
                }
            }
        }
    }

    fun toggleRule(ruleKey: String) {
        viewModelScope.launch {
            val current = _rules.value.find { it.ruleKey == ruleKey } ?: return@launch
            dao.setEnabled(ruleKey, !current.enabled)
        }
    }

    fun toggleRuleById(id: Long) {
        viewModelScope.launch {
            val current = _rules.value.find { it.id == id } ?: return@launch
            dao.setEnabledById(id, !current.enabled)
            _toastMsg.value = if (!current.enabled) "规则已启用" else "规则已停用"
        }
    }

    fun createUserRule(name: String, desc: String, conditions: String?, action: String) {
        viewModelScope.launch {
            val maxOrder = dao.getMaxSortOrder()
            val newRule = DupRuleConfigEntity(
                ruleKey = "user_${System.currentTimeMillis()}_${(0..9999).random()}",
                ruleName = name,
                enabled = true,
                description = desc,
                isBuiltin = false,
                conditions = conditions,
                action = action,
                sortOrder = maxOrder + 1,
            )
            dao.insertUserRule(newRule)
            _toastMsg.value = "自定义规则已创建"
        }
    }

    fun updateUserRule(id: Long, name: String, desc: String, conditions: String?, action: String) {
        viewModelScope.launch {
            dao.updateUserRule(id, name, desc, conditions, action)
            _toastMsg.value = "自定义规则已更新"
        }
    }

    fun deleteUserRule(id: Long) {
        viewModelScope.launch {
            val deleted = dao.deleteUserRule(id)
            if (deleted > 0) {
                _toastMsg.value = "自定义规则已删除"
            } else {
                _toastMsg.value = "内置规则不可删除"
            }
        }
    }

    fun clearToast() {
        _toastMsg.value = null
    }
}
