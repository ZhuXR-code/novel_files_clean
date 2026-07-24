package com.filescanner.app.ui.screens.settings

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.filescanner.app.ui.components.AppButton
import com.filescanner.app.ui.components.AppOutlinedButton
import com.filescanner.app.ui.components.CardItem
import com.filescanner.app.ui.components.TopBar
import org.json.JSONArray
import org.json.JSONObject

/** 一条匹配规则：对某个字段写正则。多条之间为「且」关系。 */
data class PatternItem(
    var field: String = "file_name",
    var regex: String = ""
)

/** 所有可选的处理项（字段）。 */
private val FIELD_OPTIONS = listOf(
    "file_name" to "文件名",
    "novel_name" to "小说名",
    "author" to "作者",
    "progress" to "进度",
    "source" to "来源",
    "file_size" to "文件大小(字节)",
    "created_date" to "创建日期"
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DupRuleConfigScreen(
    onBack: () -> Unit,
    viewModel: DupRuleConfigViewModel = viewModel()
) {
    val rules by viewModel.rules.collectAsState()
    val toastMsg by viewModel.toastMsg.collectAsState()

    var showDialog by remember { mutableStateOf(false) }
    var editId by remember { mutableStateOf<Long?>(null) }
    var dialogName by remember { mutableStateOf("") }
    var dialogDesc by remember { mutableStateOf("") }
    var dialogAction by remember { mutableStateOf("check") }
    var dialogPatterns by remember { mutableStateOf(mutableStateListOf(PatternItem())) }

    // 展示 toast
    LaunchedEffect(toastMsg) {
        toastMsg?.let { viewModel.clearToast() }
    }

    val openAdd = {
        editId = null
        dialogName = ""
        dialogDesc = ""
        dialogAction = "check"
        dialogPatterns.clear()
        dialogPatterns.add(PatternItem())
        showDialog = true
    }

    Scaffold(
        topBar = {
            TopBar(
                title = "勾选重复规则",
                onBack = onBack,
                actions = {
                    IconButton(onClick = openAdd) {
                        Icon(Icons.Filled.Add, contentDescription = "添加自定义规则")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                "选择「勾选重复」时应用的检测规则。内置规则不可删除；自定义规则可增删改。" +
                        "自定义规则：选择要处理的项并填写正则表达式，命中后执行对应动作。",
                fontSize = 13.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 8.dp)
            )

            // 内置规则区
            val builtinRules = rules.filter { it.isBuiltin }
            val userRules = rules.filter { !it.isBuiltin }
            if (builtinRules.isNotEmpty()) {
                Text("内置规则（不可删除）", fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontWeight = FontWeight.Medium)
                builtinRules.forEach { rule ->
                    RuleCard(rule = rule, isBuiltin = true,
                        onToggle = { viewModel.toggleRuleById(rule.id) })
                }
            }

            // 自定义规则区
            if (userRules.isNotEmpty()) {
                Spacer(Modifier.height(4.dp))
                Text("自定义规则", fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontWeight = FontWeight.Medium)
                userRules.forEach { rule ->
                    RuleCard(rule = rule, isBuiltin = false,
                        onToggle = { viewModel.toggleRuleById(rule.id) },
                        onEdit = {
                            editId = rule.id
                            dialogName = rule.ruleName
                            dialogDesc = rule.description
                            dialogAction = rule.action ?: "check"
                            dialogPatterns.clear()
                            val pats = parsePatterns(rule.conditions)
                            if (pats.isEmpty()) dialogPatterns.add(PatternItem())
                            else dialogPatterns.addAll(pats)
                            showDialog = true
                        },
                        onDelete = { viewModel.deleteUserRule(rule.id) }
                    )
                }
            }

            if (rules.isEmpty()) {
                Text("暂无规则", fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            Spacer(Modifier.height(8.dp))
            AppOutlinedButton(onClick = openAdd, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.padding(end = 4.dp))
                Text("添加自定义规则")
            }

            Spacer(Modifier.height(8.dp))
            Text("提示：修改后立即生效，下次执行\"勾选重复\"时按新规则执行。",
                fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }

    // 编辑弹窗
    if (showDialog) {
        UserRuleDialog(
            editId = editId,
            name = dialogName,
            desc = dialogDesc,
            action = dialogAction,
            patterns = dialogPatterns,
            onNameChange = { dialogName = it },
            onDescChange = { dialogDesc = it },
            onActionChange = { dialogAction = it },
            onPatternsChange = { newList ->
                // 注意：newList 就是 dialogPatterns 自身引用，必须先快照再清空，
                // 否则 clear() 后 addAll(it) 会加回一个已空的列表，导致全部条件丢失。
                val snapshot = ArrayList(newList)
                dialogPatterns.clear()
                dialogPatterns.addAll(snapshot)
            },
            onDismiss = { showDialog = false },
            onSave = {
                if (editId != null) {
                    viewModel.updateUserRule(editId!!, dialogName, dialogDesc,
                        serializePatterns(dialogPatterns), dialogAction)
                } else {
                    viewModel.createUserRule(dialogName, dialogDesc,
                        serializePatterns(dialogPatterns), dialogAction)
                }
                showDialog = false
            }
        )
    }
}

@Composable
private fun RuleCard(
    rule: DupRuleItem,
    isBuiltin: Boolean,
    onToggle: () -> Unit,
    onEdit: (() -> Unit)? = null,
    onDelete: (() -> Unit)? = null,
) {
    CardItem {
        Row(
            modifier = Modifier.fillMaxWidth().padding(start = 14.dp, end = 4.dp, top = 4.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(rule.ruleName,
                        fontWeight = FontWeight.Medium,
                        fontSize = MaterialTheme.typography.titleSmall.fontSize)
                    Spacer(Modifier.width(6.dp))
                    Text(
                        if (isBuiltin) "内置" else "自定义",
                        fontSize = 10.sp,
                        color = if (isBuiltin) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.tertiary,
                        fontWeight = FontWeight.Bold
                    )
                }
                val descText = if (isBuiltin) rule.description
                else "${if (rule.action == "protect") "🛡️保护" else "✓勾选"} - ${rule.description}"
                Text(descText, fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 2.dp))
            }
            if (!isBuiltin) {
                IconButton(onClick = { onEdit?.invoke() }, modifier = Modifier.width(36.dp).height(36.dp)) {
                    Icon(Icons.Filled.Edit, contentDescription = "编辑",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.height(18.dp))
                }
                IconButton(onClick = { onDelete?.invoke() }, modifier = Modifier.width(36.dp).height(36.dp)) {
                    Icon(Icons.Filled.Delete, contentDescription = "删除",
                        tint = MaterialTheme.colorScheme.error, modifier = Modifier.height(18.dp))
                }
            }
            Switch(checked = rule.enabled, onCheckedChange = { onToggle() })
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun UserRuleDialog(
    editId: Long?,
    name: String,
    desc: String,
    action: String,
    patterns: MutableList<PatternItem>,
    onNameChange: (String) -> Unit,
    onDescChange: (String) -> Unit,
    onActionChange: (String) -> Unit,
    onPatternsChange: (MutableList<PatternItem>) -> Unit,
    onDismiss: () -> Unit,
    onSave: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (editId != null) "编辑自定义规则" else "添加自定义规则", fontWeight = FontWeight.Bold) },
        text = {
            Column(
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.verticalScroll(rememberScrollState())
            ) {
                OutlinedTextField(value = name, onValueChange = onNameChange,
                    label = { Text("规则名称") }, singleLine = true,
                    modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = desc, onValueChange = onDescChange,
                    label = { Text("备注说明（可选）") }, singleLine = true,
                    modifier = Modifier.fillMaxWidth())

                Text("动作", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                    SegmentedButton(
                        selected = action == "check",
                        onClick = { onActionChange("check") },
                        shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2)
                    ) { Text("勾选") }
                    SegmentedButton(
                        selected = action == "protect",
                        onClick = { onActionChange("protect") },
                        shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2)
                    ) { Text("🛡️ 保护") }
                }
                Text(
                    "匹配条件：对所选「项」的内容用正则匹配，以下每条都需满足才命中本规则。",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                patterns.forEachIndexed { index, pat ->
                    PatternRow(
                        pattern = pat,
                        onFieldChange = {
                            patterns[index] = pat.copy(field = it)
                            onPatternsChange(patterns)
                        },
                        onRegexChange = {
                            patterns[index] = pat.copy(regex = it)
                            onPatternsChange(patterns)
                        },
                        onRemove = {
                            if (patterns.size > 1) {
                                patterns.removeAt(index)
                                onPatternsChange(patterns)
                            }
                        },
                        canRemove = patterns.size > 1
                    )
                }
                AppOutlinedButton(onClick = {
                    patterns.add(PatternItem())
                    onPatternsChange(patterns)
                }, modifier = Modifier.fillMaxWidth()) {
                    Text("＋ 添加匹配项")
                }
            }
        },
        confirmButton = {
            AppButton(onClick = onSave) {
                Text("保存")
            }
        },
        dismissButton = {
            AppOutlinedButton(onClick = onDismiss) { Text("取消") }
        }
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PatternRow(
    pattern: PatternItem,
    onFieldChange: (String) -> Unit,
    onRegexChange: (String) -> Unit,
    onRemove: () -> Unit,
    canRemove: Boolean,
) {
    var testInput by remember { mutableStateOf("") }
    var testResult by remember { mutableStateOf<Boolean?>(null) }
    val regexError = remember(pattern.regex) {
        if (pattern.regex.isBlank()) null
        else try { Regex(pattern.regex); null } catch (e: Exception) { e.message }
    }
    val canRun = pattern.regex.isNotBlank() && testInput.isNotBlank() && regexError == null

    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        shape = RoundedCornerShape(10.dp),
        border = BorderStroke(0.5.dp, MaterialTheme.colorScheme.outlineVariant),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("如果", fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.width(6.dp))
                DropdownField(
                    options = FIELD_OPTIONS,
                    selected = pattern.field,
                    onSelected = onFieldChange,
                    modifier = Modifier.weight(1f)
                )
                if (canRemove) {
                    IconButton(onClick = onRemove,
                        modifier = Modifier.width(32.dp).height(32.dp)) {
                        Icon(Icons.Filled.Close, contentDescription = "删除匹配项")
                    }
                }
            }
            OutlinedTextField(
                value = pattern.regex,
                onValueChange = {
                    onRegexChange(it)
                    testResult = null
                },
                label = { Text("正则表达式") },
                singleLine = true,
                isError = regexError != null,
                supportingText = if (regexError != null) {
                    { Text("正则无效：$regexError", fontSize = 11.sp) }
                } else null,
                modifier = Modifier.fillMaxWidth()
            )
            Text(
                "示例：文件名含「水印」→ 水印；以「完结」开头 → ^完结；作者等于张三 → ^张三$",
                fontSize = 10.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            // ── 测试区：输入样例文本，点「运行测试」查看本正则是否命中 ──
            Text("测试本正则（可选）：输入一段样例文本，点「运行测试」查看是否命中",
                fontSize = 10.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedTextField(
                value = testInput,
                onValueChange = {
                    testInput = it
                    testResult = null
                },
                placeholder = { Text("例如：某某小说_水印.txt") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                AppOutlinedButton(
                    onClick = {
                        testResult = try {
                            Regex(pattern.regex).containsMatchIn(testInput)
                        } catch (_: Exception) { null }
                    },
                    enabled = canRun
                ) { Text("运行测试") }
                when (testResult) {
                    null -> Text(
                        if (canRun) "（未运行）" else "（请先填正则与样例文本）",
                        fontSize = 10.sp, color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    true -> Text("✓ 命中", fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Medium)
                    false -> Text("✗ 未命中", fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.error, fontWeight = FontWeight.Medium)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DropdownField(
    options: List<Pair<String, String>>,
    selected: String,
    onSelected: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    val label = options.find { it.first == selected }?.second ?: selected
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
        modifier = modifier
    ) {
        OutlinedTextField(
            value = label,
            onValueChange = {},
            readOnly = true,
            singleLine = true,
            modifier = Modifier.menuAnchor(MenuAnchorType.PrimaryNotEditable),
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) }
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            options.forEach { opt ->
                DropdownMenuItem(
                    text = { Text(opt.second) },
                    onClick = {
                        onSelected(opt.first)
                        expanded = false
                    }
                )
            }
        }
    }
}

/** 把旧格式的 op+value 尽量转成正则，便于兼容已有自定义规则。转换不出的返回空串。 */
private fun oldOpToRegex(op: String, value: String): String {
    if (value.isBlank()) return ""
    val esc = Regex.escape(value)
    return when (op) {
        "contains" -> esc
        "not_contains" -> "(?s)^(?:(?!$esc).)*$"
        "starts_with" -> "^$esc"
        "ends_with" -> "$esc$"
        "eq" -> "^$esc$"
        "neq" -> "(?s)^(?:(?!$esc).)*$"
        "regex" -> value
        else -> ""
    }
}

private fun parsePatterns(json: String?): List<PatternItem> {
    if (json.isNullOrBlank() || json == "[]") return emptyList()
    return try {
        val arr = JSONArray(json)
        val items = mutableListOf<PatternItem>()
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            val field = obj.optString("field", "file_name")
            val regex = if (obj.has("regex")) {
                obj.optString("regex", "")
            } else {
                oldOpToRegex(obj.optString("op", "eq"), obj.optString("value", ""))
            }
            items.add(PatternItem(field = field, regex = regex))
        }
        items
    } catch (_: Exception) { emptyList() }
}

private fun serializePatterns(patterns: List<PatternItem>): String {
    val arr = JSONArray()
    for (p in patterns) {
        if (p.regex.isBlank()) continue
        val obj = JSONObject()
        obj.put("field", p.field)
        obj.put("regex", p.regex)
        arr.put(obj)
    }
    return if (arr.length() == 0) "[]" else arr.toString()
}
