package com.bookscleanandroid.app.ui.screens.settings

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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
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
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Checkbox
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.filled.PlaylistAdd
import androidx.compose.material3.Text
import com.bookscleanandroid.app.ui.components.AppOutlinedButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import kotlinx.coroutines.launch
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.bookscleanandroid.app.R
import com.bookscleanandroid.app.data.database.entity.KeywordReplaceRuleEntity
import com.bookscleanandroid.app.ui.components.CardItem
import com.bookscleanandroid.app.ui.components.TopBar
import com.bookscleanandroid.app.ui.components.AppButton
import com.bookscleanandroid.app.util.KeywordReplace

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
    var fabMenu by remember { mutableStateOf(false) }
    var batchOpen by remember { mutableStateOf(false) }
    var searchOpen by remember { mutableStateOf(false) }
    var searchQuery by remember { mutableStateOf("") }
    // null=无待确认操作；true=批量启用；false=批量不启用
    var batchTarget by remember { mutableStateOf<Boolean?>(null) }
    val snackbarHostState = remember { SnackbarHostState() }
    val coroutineScope = rememberCoroutineScope()
    val context = LocalContext.current

    val filteredRules = if (searchQuery.isBlank()) {
        rules
    } else {
        val q = searchQuery.trim()
        rules.filter {
            it.pattern.contains(q, ignoreCase = true) ||
                it.replacement.contains(q, ignoreCase = true)
        }
    }

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
            FloatingActionButton(onClick = { fabMenu = true }) {
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

            // 可展开 / 折叠的搜索栏
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        searchOpen = !searchOpen
                        if (!searchOpen) searchQuery = ""
                    }
                    .padding(horizontal = 16.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    Icons.Filled.Search,
                    contentDescription = stringResource(R.string.search_rules),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(18.dp)
                )
                Text(
                    stringResource(R.string.search_rules),
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 6.dp)
                )
                Spacer(Modifier.weight(1f))
                Icon(
                    if (searchOpen) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(20.dp)
                )
            }

            if (searchOpen) {
                OutlinedTextField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 4.dp),
                    placeholder = { Text(stringResource(R.string.search_rules_hint)) },
                    leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                    singleLine = true
                )
            }

            // 批量启用 / 不启用：仅作用于当前列表（搜索命中）的规则，直接写库
            if (filteredRules.isNotEmpty()) {
                val enabledCount = filteredRules.count { it.enabled }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        stringResource(
                            R.string.batch_enable_summary,
                            filteredRules.size, enabledCount, filteredRules.size - enabledCount
                        ),
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(Modifier.weight(1f))
                    AppOutlinedButton(
                        onClick = { batchTarget = true },
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(
                            horizontal = 12.dp, vertical = 4.dp
                        )
                    ) { Text(stringResource(R.string.batch_enable_all), fontSize = 12.sp) }
                    Spacer(Modifier.width(8.dp))
                    AppOutlinedButton(
                        onClick = { batchTarget = false },
                        contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(
                            horizontal = 12.dp, vertical = 4.dp
                        )
                    ) { Text(stringResource(R.string.batch_disable_all), fontSize = 12.sp) }
                }
            }

            if (filteredRules.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        if (searchQuery.isBlank()) stringResource(R.string.no_rules)
                        else stringResource(R.string.no_match_rules),
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
                    items(filteredRules, key = { it.id }) { rule ->
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

    // 批量启用 / 不启用 确认弹窗
    if (batchTarget != null) {
        val target = batchTarget!!
        val count = filteredRules.size
        val actionText = stringResource(
            if (target) R.string.batch_enable_all else R.string.batch_disable_all
        )
        AlertDialog(
            onDismissRequest = { batchTarget = null },
            title = { Text(actionText) },
            text = {
                Text(
                    stringResource(
                        if (searchQuery.isBlank()) R.string.batch_confirm_all
                        else R.string.batch_confirm_search,
                        count, actionText
                    )
                )
            },
            confirmButton = {
                AppButton(onClick = {
                    val ids = filteredRules.map { it.id }
                    viewModel.setEnabledBatch(ids, target) { n ->
                        coroutineScope.launch {
                            snackbarHostState.showSnackbar(
                                context.getString(R.string.batch_done, actionText, n)
                            )
                        }
                    }
                    batchTarget = null
                }) { Text(stringResource(R.string.confirm)) }
            },
            dismissButton = {
                AppOutlinedButton(onClick = { batchTarget = null }) {
                    Text(stringResource(R.string.cancel))
                }
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

    // 批量新增弹窗
    DropdownMenu(
        expanded = fabMenu,
        onDismissRequest = { fabMenu = false }
    ) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.add_rule)) },
            onClick = {
                fabMenu = false
                openEdit(null)
            },
            leadingIcon = { Icon(Icons.Filled.Add, contentDescription = null) }
        )
        DropdownMenuItem(
            text = { Text(stringResource(R.string.batch_add_rule)) },
            onClick = {
                fabMenu = false
                batchOpen = true
            },
            leadingIcon = { Icon(Icons.Filled.PlaylistAdd, contentDescription = null) }
        )
    }

    if (batchOpen) {
        BatchKeywordReplaceDialog(
            scope = scope,
            onDismiss = { batchOpen = false },
            onConfirm = { mode, text, enabled ->
                viewModel.batchAdd(scope, mode, text, enabled) {
                    batchOpen = false
                }
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BatchKeywordReplaceDialog(
    scope: String,
    onDismiss: () -> Unit,
    onConfirm: (mode: String, text: String, enabled: Boolean) -> Unit
) {
    var mode by remember { mutableStateOf("remove") } // remove | replace
    var text by remember { mutableStateOf("") }
    var enabled by remember { mutableStateOf(true) }

    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            AppButton(onClick = {
                val lines = text.lines().map { it.trim() }.filter { it.isNotEmpty() }
                if (lines.isEmpty()) return@AppButton
                if (mode == "replace") {
                    val bad = lines.firstOrNull {
                        val idx = it.indexOf("||")
                        idx <= 0 || it.substring(0, idx).trim().isEmpty()
                    }
                    if (bad != null) return@AppButton
                }
                onConfirm(mode, text, enabled)
            }) { Text(stringResource(R.string.save)) }
        },
        dismissButton = {
            AppOutlinedButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
        },
        title = { Text(stringResource(R.string.batch_add_rule_title)) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    FilterChip(
                        selected = mode == "remove",
                        onClick = { mode = "remove" },
                        label = { Text(stringResource(R.string.batch_mode_remove)) }
                    )
                    Spacer(Modifier.width(8.dp))
                    FilterChip(
                        selected = mode == "replace",
                        onClick = { mode = "replace" },
                        label = { Text(stringResource(R.string.batch_mode_replace)) }
                    )
                    Spacer(Modifier.width(8.dp))
                    Checkbox(checked = enabled, onCheckedChange = { enabled = it })
                    Text(stringResource(R.string.rule_enabled), fontSize = 12.sp)
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    if (mode == "remove") stringResource(R.string.batch_hint_remove)
                    else stringResource(R.string.batch_hint_replace),
                    fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 200.dp),
                    placeholder = { Text(if (mode == "remove") stringResource(R.string.batch_placeholder_remove) else stringResource(R.string.batch_placeholder_replace)) },
                    singleLine = false
                )
            }
        }
    )
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
                .padding(horizontal = 12.dp, vertical = 6.dp),
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
            IconButton(onClick = onEdit, modifier = Modifier.size(36.dp)) {
                Icon(Icons.Filled.Edit, contentDescription = stringResource(R.string.edit_rule),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            IconButton(onClick = onDelete, modifier = Modifier.size(36.dp)) {
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
