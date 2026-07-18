package com.filescanner.app.ui.screens.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import com.filescanner.app.ui.components.AppOutlinedButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.filescanner.app.R
import com.filescanner.app.data.database.entity.KeywordReplaceRuleEntity
import com.filescanner.app.ui.components.CardItem
import com.filescanner.app.ui.components.TopBar
import com.filescanner.app.ui.components.AppButton
import com.filescanner.app.util.KeywordReplace

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun KeywordReplaceScreen(
    onBack: () -> Unit,
    viewModel: KeywordReplaceViewModel = viewModel()
) {
    val scanRules by viewModel.scanRules.collectAsStateWithLifecycle()
    val parseRules by viewModel.parseRules.collectAsStateWithLifecycle()

    var scope by remember { mutableStateOf(KeywordReplace.SCOPE_SCAN) }
    val rules = if (scope == KeywordReplace.SCOPE_SCAN) scanRules else parseRules

    var editing by remember { mutableStateOf<KeywordReplaceRuleEntity?>(null) }
    var showAdd by remember { mutableStateOf(false) }
    var toDelete by remember { mutableStateOf<KeywordReplaceRuleEntity?>(null) }
    val snackbarHostState = remember { SnackbarHostState() }

    val openEdit = { rule: KeywordReplaceRuleEntity? ->
        if (rule == null) {
            showAdd = true
        } else {
            editing = rule
        }
    }

    Scaffold(
        topBar = { TopBar(title = stringResource(R.string.keyword_replace), onBack = onBack) },
        snackbarHost = { SnackbarHost(snackbarHostState) },
        floatingActionButton = {
            FloatingActionButton(onClick = { openEdit(null) }) {
                Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.add_rule))
            }
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            // 作用域切换：扫描阶段（文件名）/ 解析阶段（书名/作者/进度/来源）
            SingleChoiceSegmentedButtonRow(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(IntrinsicSize.Max)
                    .padding(horizontal = 12.dp, vertical = 8.dp)
            ) {
                SegmentedButton(
                    selected = scope == KeywordReplace.SCOPE_SCAN,
                    onClick = { scope = KeywordReplace.SCOPE_SCAN },
                    shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2),
                    modifier = Modifier.fillMaxHeight()
                ) { Text(stringResource(R.string.scope_scan)) }
                SegmentedButton(
                    selected = scope == KeywordReplace.SCOPE_PARSE,
                    onClick = { scope = KeywordReplace.SCOPE_PARSE },
                    shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2),
                    modifier = Modifier.fillMaxHeight()
                ) { Text(stringResource(R.string.scope_parse)) }
            }

            Text(
                stringResource(R.string.keyword_replace_hint),
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
            )

            if (rules.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        stringResource(R.string.no_rules),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 14.sp
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(rules, key = { it.id }) { rule ->
                        RuleCard(
                            rule = rule,
                            onToggle = { viewModel.setEnabled(rule.id, it) },
                            onEdit = { openEdit(rule) },
                            onDelete = { toDelete = rule }
                        )
                    }
                }
            }
        }
    }

    // 新增 / 编辑 弹窗
    if (showAdd) {
        RuleEditDialog(
            scope = scope,
            onDismiss = { showAdd = false },
            onConfirm = { pattern, replacement, order, enabled ->
                val newRule = KeywordReplaceRuleEntity(
                    scope = scope,
                    pattern = pattern,
                    replacement = replacement,
                    sortOrder = order,
                    enabled = enabled
                )
                viewModel.upsert(newRule)
                showAdd = false
            }
        )
    }
    if (editing != null) {
        val r = editing!!
        RuleEditDialog(
            scope = r.scope,
            initial = r,
            onDismiss = { editing = null },
            onConfirm = { pattern, replacement, order, enabled ->
                viewModel.upsert(
                    r.copy(
                        pattern = pattern,
                        replacement = replacement,
                        sortOrder = order,
                        enabled = enabled
                    )
                )
                editing = null
            }
        )
    }

    if (toDelete != null) {
        AlertDialog(
            onDismissRequest = { toDelete = null },
            title = { Text(stringResource(R.string.delete_rule)) },
            text = { Text(stringResource(R.string.delete_rule_confirm)) },
            confirmButton = {
                AppButton(
                    onClick = {
                        viewModel.delete(toDelete!!)
                        toDelete = null
                    },
                    containerColor = MaterialTheme.colorScheme.error,
                    contentColor = MaterialTheme.colorScheme.onError
                ) { Text(stringResource(R.string.confirm)) }
            },
            dismissButton = {
                AppOutlinedButton(onClick = { toDelete = null }) { Text(stringResource(R.string.cancel)) }
            }
        )
    }
}

@Composable
private fun RuleCard(
    rule: KeywordReplaceRuleEntity,
    onToggle: (Boolean) -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    CardItem {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Switch(checked = rule.enabled, onCheckedChange = onToggle)
            Column(modifier = Modifier.weight(1f).padding(start = 8.dp)) {
                Text(
                    rule.pattern.ifBlank { "（空）" },
                    fontWeight = FontWeight.Medium,
                    fontSize = 14.sp,
                    maxLines = 1
                )
                val rep = if (rule.replacement.isEmpty()) stringResource(R.string.delete_text)
                else rule.replacement
                Text(
                    stringResource(R.string.replace_to, rep),
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1
                )
            }
            IconButton(onClick = onEdit) {
                Icon(Icons.Filled.Edit, contentDescription = stringResource(R.string.edit_rule),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            IconButton(onClick = onDelete) {
                Icon(Icons.Filled.Delete, contentDescription = stringResource(R.string.delete_rule),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RuleEditDialog(
    scope: String,
    initial: KeywordReplaceRuleEntity? = null,
    onDismiss: () -> Unit,
    onConfirm: (pattern: String, replacement: String, order: Int, enabled: Boolean) -> Unit
) {
    var pattern by remember { mutableStateOf(initial?.pattern ?: "") }
    var replacement by remember { mutableStateOf(initial?.replacement ?: "") }
    var orderText by remember { mutableStateOf((initial?.sortOrder ?: 0).toString()) }
    var enabled by remember { mutableStateOf(initial?.enabled ?: true) }
    var patternError by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (initial == null) stringResource(R.string.add_rule) else stringResource(R.string.edit_rule)) },
        text = {
            Column {
                Text(
                    if (scope == KeywordReplace.SCOPE_SCAN) stringResource(R.string.scope_scan)
                    else stringResource(R.string.scope_parse),
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = pattern,
                    onValueChange = { pattern = it; patternError = false },
                    label = { Text(stringResource(R.string.rule_pattern)) },
                    placeholder = { Text(stringResource(R.string.rule_pattern_hint)) },
                    singleLine = true,
                    isError = patternError,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = replacement,
                    onValueChange = { replacement = it },
                    label = { Text(stringResource(R.string.rule_replacement)) },
                    placeholder = { Text(stringResource(R.string.rule_replacement_hint)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = orderText,
                    onValueChange = { orderText = it.filter { c -> c.isDigit() } },
                    label = { Text(stringResource(R.string.rule_order)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(stringResource(R.string.rule_enabled))
                    Spacer(Modifier.weight(1f))
                    Switch(checked = enabled, onCheckedChange = { enabled = it })
                }
            }
        },
        confirmButton = {
            AppButton(onClick = {
                if (pattern.isBlank()) {
                    patternError = true
                    return@AppButton
                }
                onConfirm(pattern.trim(), replacement, orderText.toIntOrNull() ?: 0, enabled)
            }) { Text(stringResource(R.string.confirm)) }
        },
        dismissButton = {
            AppOutlinedButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
        }
    )
}
