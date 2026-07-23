package com.filescanner.app.ui.screens.library

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DoneAll
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Sort
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import com.filescanner.app.ui.components.AppOutlinedButton
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.TriStateCheckbox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.filescanner.app.R
import com.filescanner.app.data.database.entity.ScannedFileEntity
import com.filescanner.app.data.database.entity.ScanRunEntity
import com.filescanner.app.data.model.NovelGroup
import com.filescanner.app.ui.screens.delete.PendingDeleteHolder
import com.filescanner.app.ui.components.CardItem
import com.filescanner.app.ui.components.TopBar
import com.filescanner.app.ui.components.AppButton
import com.filescanner.app.util.FormatUtil
import com.filescanner.app.util.LogUtil
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun LibraryScreen(
    onBack: () -> Unit,
    onNavigateToDeleteConfirm: () -> Unit,
    onOpenFile: (Long) -> Unit,
    initialRunId: Long = -1L,
    viewModel: LibraryViewModel = viewModel()
) {
    val currentRunId by viewModel.currentRunId.collectAsStateWithLifecycle()
    // 从扫描结果页进入时携带 runId，直达本次已扫描文件列表（停止/完成后保留结果）
    LaunchedEffect(initialRunId) {
        if (initialRunId > 0) viewModel.setCurrentRunId(initialRunId)
    }
    val scanRuns by viewModel.scanRuns.collectAsStateWithLifecycle(initialValue = emptyList())

    if (currentRunId == null) {
        RunListScreen(
            runs = scanRuns,
            onOpen = { viewModel.setCurrentRunId(it.id) },
            onDelete = { viewModel.deleteRun(it.id) },
            onBack = onBack
        )
    } else {
        val run = scanRuns.find { it.id == currentRunId }
        RunFilesScreen(
            viewModel = viewModel,
            runName = run?.name ?: stringResource(R.string.library),
            onBackToList = { viewModel.setCurrentRunId(null) },
            onNavigateToDeleteConfirm = onNavigateToDeleteConfirm,
            onOpenFile = onOpenFile
        )
    }
}

/** 文库（每次扫描）列表：点进去看该次扫描的文件。 */
@Composable
private fun RunListScreen(
    runs: List<ScanRunEntity>,
    onOpen: (ScanRunEntity) -> Unit,
    onDelete: (ScanRunEntity) -> Unit,
    onBack: () -> Unit
) {
    var toDelete by remember { mutableStateOf<ScanRunEntity?>(null) }
    Scaffold(
        topBar = { TopBar(title = stringResource(R.string.library), onBack = onBack) }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp)
        ) {
            if (runs.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        stringResource(R.string.run_list_empty),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 14.sp
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    items(runs, key = { it.id }) { run ->
                        CardItem(onClick = { onOpen(run) }) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(14.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        run.name.ifBlank { stringResource(R.string.unnamed_config) },
                                        fontWeight = MaterialTheme.typography.titleMedium.fontWeight,
                                        fontSize = MaterialTheme.typography.titleMedium.fontSize,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                    if (run.folderName.isNotBlank()) {
                                        Text(
                                            run.folderName,
                                            fontSize = 12.sp,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                            modifier = Modifier.padding(top = 2.dp)
                                        )
                                    }
                                    Text(
                                        stringResource(
                                            R.string.run_summary,
                                            run.fileCount,
                                            formatDate(run.createdAt)
                                        ),
                                        fontSize = 12.sp,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.padding(top = 4.dp)
                                    )
                                }
                                IconButton(onClick = { toDelete = run }) {
                                    Icon(
                                        Icons.Filled.Delete,
                                        contentDescription = stringResource(R.string.delete_run),
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (toDelete != null) {
        AlertDialog(
            onDismissRequest = { toDelete = null },
            title = { Text(stringResource(R.string.delete_run)) },
            text = { Text(stringResource(R.string.delete_run_confirm)) },
            confirmButton = {
                AppButton(
                    onClick = {
                        onDelete(toDelete!!)
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

/** 单个文库内的文件列表（列表/合集模式），即原来的文库内容。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RunFilesScreen(
    viewModel: LibraryViewModel,
    runName: String,
    onBackToList: () -> Unit,
    onNavigateToDeleteConfirm: () -> Unit,
    onOpenFile: (Long) -> Unit
) {
    // 真·页码分页：当前页数据 + 满足条件总数，均由 ViewModel 按 currentPage 查询
    val listPageState by viewModel.listPageState.collectAsStateWithLifecycle()
    val groupPageState by viewModel.groupPageState.collectAsStateWithLifecycle()
    val currentPage by viewModel.currentPage.collectAsStateWithLifecycle()
    val filter by viewModel.filter.collectAsStateWithLifecycle()
    val checkedCount by viewModel.checkedCount.collectAsStateWithLifecycle()
    val toast by viewModel.toast.collectAsStateWithLifecycle()
    val query by viewModel.query.collectAsStateWithLifecycle()
    val groupMode by viewModel.groupMode.collectAsStateWithLifecycle()
    val expandedGroups by viewModel.expandedGroups.collectAsStateWithLifecycle()
    val groupFiles by viewModel.groupFiles.collectAsStateWithLifecycle()
    val groupCheckedCounts by viewModel.groupCheckedCounts.collectAsStateWithLifecycle()
    val minCount by viewModel.groupMinCount.collectAsStateWithLifecycle()
    val maxCount by viewModel.groupMaxCount.collectAsStateWithLifecycle()
    val excludeNames by viewModel.groupExcludeNames.collectAsStateWithLifecycle()
    val pageSize by viewModel.pageSize.collectAsStateWithLifecycle()
    val duplicateProgress by viewModel.duplicateProgress.collectAsStateWithLifecycle()
    // 分页导航条用的总数：合集模式=分组数，列表模式=文件数
    val totalCount = if (groupMode) groupPageState.total else listPageState.total

    var sortMenu by remember { mutableStateOf(false) }
    var moreMenu by remember { mutableStateOf(false) }
    var showGroupSettings by remember { mutableStateOf(false) }
    // 批量删除选中：先弹窗让用户选择“仅删除记录”或“删除记录和源文件”
    var showDeleteChoice by remember { mutableStateOf(false) }
    // 搜索框默认隐藏，顶部搜索图标点击后显示；再点切换回隐藏
    var searchVisible by remember { mutableStateOf(false) }
    // 顶部"模式切换 + 筛选"工具栏可收起/展开（默认展开），收起按钮在搜索按钮旁
    var toolbarExpanded by remember { mutableStateOf(true) }
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()

    // 翻页 / 切筛选 / 换模式 / 改每页条数 / 搜索 后，把列表滚回顶部（每页是独立数据集）。
    // 用 rememberSaveable 记录上次触发回顶的参数组合：仅当这些参数真正变化时才回顶。
    // 从小说明细页返回时（本组件被重建、LaunchedEffect 重新执行，但参数未变），不再强制回顶，
    // 从而让 rememberLazyListState 恢复原滚动位置，自动定位到点进去的那本小说。
    var lastTopKey by rememberSaveable { mutableStateOf("") }
    val topKey = "$currentPage|$filter|$groupMode|$pageSize|$query"
    LaunchedEffect(topKey) {
        when {
            lastTopKey.isEmpty() -> lastTopKey = topKey // 首次进入：记录基线，不滚动
            lastTopKey != topKey -> {
                listState.scrollToItem(0)
                lastTopKey = topKey
            }
        }
    }


    LaunchedEffect(toast) {
        toast?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearToast()
        }
    }

    if (showGroupSettings) {
        GroupSettingsDialog(
            initMin = minCount,
            initMax = maxCount,
            initExclude = excludeNames,
            onDismiss = { showGroupSettings = false },
                onConfirm = { min, max, exclude ->
                    viewModel.applyGroupFilter(min, max, exclude)
                    showGroupSettings = false
                }
            )
    }

    if (showDeleteChoice) {
        var delSource by remember { mutableStateOf(false) }
        AlertDialog(
            onDismissRequest = { showDeleteChoice = false },
            title = { Text(stringResource(R.string.delete_choice_title)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { delSource = false }
                            .padding(4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(selected = !delSource, onClick = { delSource = false })
                        Column(modifier = Modifier.padding(start = 8.dp)) {
                            Text(stringResource(R.string.delete_record_only))
                            Text(
                                stringResource(R.string.delete_record_only_hint),
                                fontSize = 12.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { delSource = true }
                            .padding(4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(selected = delSource, onClick = { delSource = true })
                        Column(modifier = Modifier.padding(start = 8.dp)) {
                            Text(stringResource(R.string.delete_record_file))
                            Text(
                                stringResource(R.string.delete_record_file_hint),
                                fontSize = 12.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            },
            confirmButton = {
                AppButton(onClick = {
                    showDeleteChoice = false
                    // 异步取已勾选 id（避免主线程查库致 ANR）
                    scope.launch {
                        PendingDeleteHolder.ids = viewModel.takeSelectionForDelete()
                        PendingDeleteHolder.deleteSource = delSource
                        onNavigateToDeleteConfirm()
                    }
                }) { Text(stringResource(R.string.confirm)) }
            },
            dismissButton = {
                AppOutlinedButton(onClick = { showDeleteChoice = false }) { Text(stringResource(R.string.cancel)) }
            }
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopBar(
                title = runName,
                onBack = onBackToList,
                actions = {
                    IconButton(onClick = { searchVisible = !searchVisible }) {
                        Icon(
                            if (searchVisible) Icons.Filled.Close else Icons.Filled.Search,
                            contentDescription = stringResource(R.string.search),
                            tint = if (searchVisible) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    // 收起/展开"模式切换 + 筛选"工具栏（放在搜索按钮旁）
                    IconButton(onClick = { toolbarExpanded = !toolbarExpanded }) {
                        Icon(
                            if (toolbarExpanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                            contentDescription = stringResource(R.string.toggle_toolbar)
                        )
                    }
                    IconButton(onClick = { sortMenu = true }) {
                        Icon(Icons.Filled.Sort, contentDescription = stringResource(R.string.sort_time))
                    }
                    // 方案 B：合集模式下，"标记重复"作为常驻主按钮（不再藏在 ⋮ 菜单里）
                    if (groupMode) {
                        IconButton(
                            onClick = { viewModel.selectDuplicates() },
                            enabled = duplicateProgress < 0
                        ) {
                            Icon(
                                imageVector = Icons.Filled.DoneAll,
                                contentDescription = stringResource(R.string.mark_duplicates),
                                tint = if (duplicateProgress < 0) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.outline
                            )
                        }
                    }
                    IconButton(onClick = { moreMenu = true }) {
                        Icon(Icons.Filled.MoreVert, contentDescription = null)
                    }
                    DropdownMenu(expanded = sortMenu, onDismissRequest = { sortMenu = false }) {
                        DropdownMenuItem(text = { Text(stringResource(R.string.sort_time)) },
                            onClick = { viewModel.setSort(SortMode.TIME); sortMenu = false })
                        DropdownMenuItem(text = { Text(stringResource(R.string.sort_name)) },
                            onClick = { viewModel.setSort(SortMode.NAME); sortMenu = false })
                        DropdownMenuItem(text = { Text(stringResource(R.string.sort_size)) },
                            onClick = { viewModel.setSort(SortMode.SIZE); sortMenu = false })
                    }
                    DropdownMenu(expanded = moreMenu, onDismissRequest = { moreMenu = false }) {
                        if (groupMode) {
                            DropdownMenuItem(text = { Text(stringResource(R.string.group_settings)) },
                                onClick = { showGroupSettings = true; moreMenu = false })
                        }
                        DropdownMenuItem(text = { Text(stringResource(R.string.mark_duplicates_name)) },
                            onClick = { viewModel.markDuplicatesByName(); moreMenu = false })
                        DropdownMenuItem(text = { Text(stringResource(R.string.clear_marked)) },
                            onClick = { viewModel.clearMarked(); moreMenu = false })
                    }
                }
            )
        },
        bottomBar = {
            if (checkedCount > 0) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    AppOutlinedButton(
                        onClick = { viewModel.clearChecked() },
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 2.dp)
                    ) {
                        Text(stringResource(R.string.clear_checked), fontSize = 11.sp)
                    }
                    Spacer(Modifier.weight(1f))
                    Text(
                        stringResource(R.string.selected_count, checkedCount),
                        fontSize = 11.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    // 批量删除按钮：只保留垃圾桶图标，避免文字在窄屏下被强制竖排换行
                    // （之前 "批量删除选中" 6 个字在已勾选数字很大时被挤到 6 行竖排）
                    AppButton(
                        onClick = { showDeleteChoice = true },
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 2.dp)
                    ) {
                        Icon(
                            Icons.Filled.Delete,
                            contentDescription = stringResource(R.string.batch_delete_selected)
                        )
                    }
                }
            }
        }
        ) { padding ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
            ) {
                Column(modifier = Modifier.fillMaxSize()) {
                // 清理步骤指示器：引导用户按 扫描→合集→标记重复→确认→删除 顺序操作
                StepIndicator(
                    groupMode = groupMode,
                    checkedCount = checkedCount,
                    duplicateRunning = duplicateProgress >= 0,
                    onGoGroup = { viewModel.setGroupMode(true) },
                    onMarkDuplicates = { viewModel.selectDuplicates() },
                    onDelete = { showDeleteChoice = true },
                )
                // 顶部"列表/合集"分段切换（与 PC 端一致），可整体收起
                if (toolbarExpanded) {
                SingleChoiceSegmentedButtonRow(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 0.dp)
                ) {
                    SegmentedButton(
                        selected = !groupMode,
                        onClick = { viewModel.setGroupMode(false) },
                        shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2),
                        // 缩小整体高度，文字与边框的上下距离随之收窄（仍能完整显示）
                        modifier = Modifier.height(32.dp)
                    ) {
                        Text(stringResource(R.string.list_mode), fontSize = 13.sp)
                    }
                    SegmentedButton(
                        selected = groupMode,
                        onClick = { viewModel.setGroupMode(true) },
                        shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2),
                        modifier = Modifier.height(32.dp)
                    ) {
                        Text(stringResource(R.string.group_mode), fontSize = 13.sp)
                    }
                }
                // 筛选 chips：列表模式显示（全部 / 已勾选 / 未勾选 / 已标记 / 未标记）；
                // 合集模式额外显示「含已勾选」（仅保留组内有已勾选文件的合集），与搜索框叠加使用
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 12.dp, vertical = 2.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    CompactChip(
                        selected = filter == FilterMode.ALL,
                        onClick = { viewModel.setFilter(FilterMode.ALL) },
                        label = stringResource(R.string.filter_all)
                    )
                    CompactChip(
                        selected = filter == FilterMode.CHECKED,
                        onClick = { viewModel.setFilter(FilterMode.CHECKED) },
                        label = stringResource(R.string.filter_checked)
                    )
                    CompactChip(
                        selected = filter == FilterMode.UNCHECKED,
                        onClick = { viewModel.setFilter(FilterMode.UNCHECKED) },
                        label = stringResource(R.string.filter_unchecked)
                    )
                    CompactChip(
                        selected = filter == FilterMode.MARKED,
                        onClick = { viewModel.setFilter(FilterMode.MARKED) },
                        label = stringResource(R.string.filter_marked)
                    )
                    CompactChip(
                        selected = filter == FilterMode.UNMARKED,
                        onClick = { viewModel.setFilter(FilterMode.UNMARKED) },
                        label = stringResource(R.string.filter_unmarked)
                    )
                    // 「含已勾选」仅合集模式有意义：只显示组内有已勾选文件的合集
                    if (groupMode) {
                        CompactChip(
                            selected = filter == FilterMode.HAS_CHECKED,
                            onClick = { viewModel.setFilter(FilterMode.HAS_CHECKED) },
                            label = stringResource(R.string.filter_has_checked)
                        )
                    }
                }
                }
            // 搜索框：仅在用户点击顶部搜索图标后才显示
            if (searchVisible) {
                OutlinedTextField(
                    value = query,
                    onValueChange = { viewModel.setQuery(it) },
                    placeholder = { Text(stringResource(R.string.search)) },
                    singleLine = true,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp)
                )
                Spacer(Modifier.height(8.dp))
            }

            // 合集计算（标记重复）进度：进行中显示进度条，便于大库下观察进度
            if (duplicateProgress >= 0) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                ) {
                    Text(
                        stringResource(R.string.computing_duplicates),
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.primary
                    )
                    Spacer(Modifier.height(4.dp))
                    LinearProgressIndicator(
                        progress = { duplicateProgress / 100f },
                        modifier = Modifier.fillMaxWidth().height(6.dp)
                    )
                }
            }

            Box(modifier = Modifier.fillMaxWidth().weight(1f)) {
                if (groupMode) {
                    GroupList(
                        listState = listState,
                        groups = groupPageState.groups,
                        loading = groupPageState.loading,
                        checkedCount = checkedCount,
                        expandedGroups = expandedGroups,
                        groupFiles = groupFiles,
                        groupCheckedCounts = groupCheckedCounts,
                        onToggleExpand = { viewModel.toggleGroupExpand(it) },
                        onToggleGroupSelectAll = { viewModel.toggleGroupSelectAll(it) },
                        onToggleSelect = { id, checked -> viewModel.toggleSelect(id, checked) },
                        onToggleMark = { id, m -> viewModel.toggleMark(id, m) },
                        onOpenFile = onOpenFile
                    )
                } else {
                    FlatList(
                        listState = listState,
                        items = listPageState.items,
                        loading = listPageState.loading,
                        checkedCount = checkedCount,
                        onToggleSelect = { id, checked -> viewModel.toggleSelect(id, checked) },
                        onToggleMark = { id, m -> viewModel.toggleMark(id, m) },
                        onOpenFile = onOpenFile
                    )
                }
            }
            // 分页导航条：大库（10w+）按每页 100/500/2000 跳页浏览；页码由状态驱动
            PageNavBar(
                totalCount = totalCount,
                pageSize = pageSize,
                currentPage = currentPage,
                onPageSizeChange = { viewModel.setPageSize(it) },
                onJumpToPage = { page -> viewModel.goToPage(page) }
            )
                // 关闭内部 Column，使下方悬浮按钮成为外层 Box 的直接子项（可使用 BoxScope.align）
                }
                // 悬浮：回到顶层 / 回到底层（像 PC 端 backNav，仅在有内容可滚动时显示）
                val showUp by remember { derivedStateOf { listState.firstVisibleItemIndex > 0 || listState.firstVisibleItemScrollOffset > 0 } }
                val showDown by remember { derivedStateOf { listState.canScrollForward } }
                Column(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(end = 16.dp, bottom = if (checkedCount > 0) 110.dp else 60.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    if (showDown) {
                        FloatingActionButton(
                            onClick = {
                                val last = (listState.layoutInfo.totalItemsCount - 1).coerceAtLeast(0)
                                scope.launch { listState.animateScrollToItem(last) }
                            },
                            modifier = Modifier.size(36.dp),
                            containerColor = MaterialTheme.colorScheme.primaryContainer,
                            contentColor = MaterialTheme.colorScheme.onPrimaryContainer
                        ) {
                            Icon(
                                Icons.Filled.ArrowDownward,
                                contentDescription = stringResource(R.string.back_to_bottom),
                                modifier = Modifier.size(20.dp)
                            )
                        }
                    }
                    if (showUp) {
                        FloatingActionButton(
                            onClick = { scope.launch { listState.animateScrollToItem(0) } },
                            modifier = Modifier.size(36.dp),
                            containerColor = MaterialTheme.colorScheme.primaryContainer,
                            contentColor = MaterialTheme.colorScheme.onPrimaryContainer
                        ) {
                            Icon(
                                Icons.Filled.ArrowUpward,
                                contentDescription = stringResource(R.string.back_to_top),
                                modifier = Modifier.size(20.dp)
                            )
                        }
                    }
                }
            }
        }
    }

@Composable
private fun FlatList(
    listState: LazyListState,
    items: List<ScannedFileEntity>,
    loading: Boolean,
    checkedCount: Int,
    onToggleSelect: (Long, Int) -> Unit,
    onToggleMark: (Long, Int) -> Unit,
    onOpenFile: (Long) -> Unit
) {
    when {
        loading && items.isEmpty() -> {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.loading), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        items.isEmpty() -> {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.no_files), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        else -> {
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                // 底部留白，避免最后一行（其右侧星标）被右下角悬浮按钮遮挡而点不到
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    top = 12.dp,
                    bottom = if (checkedCount > 0) 136.dp else 72.dp
                ),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(
                    items = items,
                    key = { it.id },
                ) { f ->
                    FileRow(
                        f = f,
                        selected = f.checked == 1,
                        onToggleSelect = { onToggleSelect(f.id, f.checked) },
                        onToggleMark = { onToggleMark(f.id, f.marked) },
                        onOpen = { onOpenFile(f.id) }
                    )
                }
            }
        }
    }
}

@Composable
private fun GroupList(
    listState: LazyListState,
    groups: List<NovelGroup>,
    loading: Boolean,
    checkedCount: Int,
    expandedGroups: Set<String>,
    groupFiles: Map<String, List<ScannedFileEntity>>,
    groupCheckedCounts: Map<String, Int>,
    onToggleExpand: (String) -> Unit,
    onToggleGroupSelectAll: (String) -> Unit,
    onToggleSelect: (Long, Int) -> Unit,
    onToggleMark: (Long, Int) -> Unit,
    onOpenFile: (Long) -> Unit
) {
    when {
        loading && groups.isEmpty() -> {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.loading), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        groups.isEmpty() -> {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.no_groups), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        else -> {
            // 扁平化懒加载：合集头作为单个 item，展开的组内文件用 items 懒加载，
            // 避免大合集（数千文件）用 forEach 一次性渲染全部 Composable 导致 OOM/ANR 闪退。
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                // 底部留白，避免末行（含其右侧星标）被右下角悬浮按钮遮挡
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    top = 12.dp,
                    bottom = if (checkedCount > 0) 136.dp else 72.dp
                ),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                groups.forEach { g ->
                    val titleKey = g.title.ifBlank { "__unparsed__" }
                    val expanded = expandedGroups.contains(g.title)
                    val files = groupFiles[g.title]
                    // 合集已勾选数：优先用 ViewModel 乐观维护的计数（勾选即时刷新，避免 RawQuery 不观测导致陈旧），
                    // 回退到数据库聚合的 checkedCount。据此判断三态复选框：0=未选、==总数=全选、其间=部分选中(-)。
                    val gChecked = groupCheckedCounts[g.title] ?: g.checkedCount
                    val groupState = when {
                        g.fileCount <= 0 -> ToggleableState.Off
                        gChecked <= 0 -> ToggleableState.Off
                        gChecked >= g.fileCount -> ToggleableState.On
                        else -> ToggleableState.Indeterminate
                    }
                    // 合集头（卡片）
                    item(key = "header::$titleKey", contentType = "groupHeader") {
                        CardItem {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { onToggleExpand(g.title) }
                                    .padding(horizontal = 12.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                TriStateCheckbox(
                                    state = groupState,
                                    onClick = { onToggleGroupSelectAll(g.title) }
                                )
                                Column(modifier = Modifier.weight(1f).padding(start = 4.dp)) {
                                    Text(
                                        g.title.ifBlank { stringResource(R.string.group_unparsed) },
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                        fontWeight = MaterialTheme.typography.titleSmall.fontWeight,
                                        fontSize = MaterialTheme.typography.titleSmall.fontSize
                                    )
                                    Spacer(Modifier.height(2.dp))
                                    Text(
                                        stringResource(R.string.group_summary, g.fileCount, FormatUtil.formatSize(g.totalSize)),
                                        fontSize = 12.sp,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                Icon(
                                    if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                    // 展开：组内文件扁平化懒加载（仅渲染可见行，大合集不再 OOM）
                    if (expanded) {
                        if (files == null) {
                            item(key = "loading::$titleKey", contentType = "loading") {
                                Box(
                                    modifier = Modifier.fillMaxWidth().padding(12.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(stringResource(R.string.loading), fontSize = 12.sp,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        } else {
                            items(
                                items = files,
                                key = { "file::$titleKey::${it.id}" },
                                contentType = { "groupFile" }
                            ) { f ->
                                GroupFileRow(
                                    f = f,
                                    selected = f.checked == 1,
                                    onToggleSelect = { onToggleSelect(f.id, f.checked) },
                                    onToggleMark = { onToggleMark(f.id, f.marked) },
                                    onOpen = { onOpenFile(f.id) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

/** 列表模式的文件卡片行。整行点击进入明细；勾选框与星标独立。 */
@Composable
private fun FileRow(
    f: ScannedFileEntity,
    selected: Boolean,
    onToggleSelect: () -> Unit,
    onToggleMark: () -> Unit,
    onOpen: () -> Unit
) {
    CardItem {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { LogUtil.i("FileRow", "row open id=${f.id}"); onOpen() }
                .padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Checkbox(checked = selected, onCheckedChange = { onToggleSelect() })
            Column(modifier = Modifier.weight(1f).padding(start = 8.dp)) {
                Text(
                    f.title.ifBlank { f.fileName },
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    fontWeight = MaterialTheme.typography.titleSmall.fontWeight,
                    fontSize = MaterialTheme.typography.titleSmall.fontSize
                )
                Spacer(Modifier.height(2.dp))
                // 原文件名（物理文件名），与解析书名不同时才显示，避免冗余
                if (f.fileName.isNotBlank() && f.fileName != f.title) {
                    Text(
                        stringResource(R.string.original_name_prefix) + f.fileName,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        fontSize = 11.sp,
                        color = MaterialTheme.colorScheme.outline
                    )
                    Spacer(Modifier.height(2.dp))
                }
                val sub = buildList {
                    if (f.author.isNotBlank()) add(f.author)
                    add(FormatUtil.formatSize(f.fileSize))
                    if (f.progress.isNotBlank()) add(f.progress)
                    if (f.source.isNotBlank()) add(stringResource(R.string.source_label) + "：" + f.source)
                }.joinToString(" · ")
                Text(
                    sub,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            IconButton(onClick = { LogUtil.i("FileRow", "mark click id=${f.id}"); onToggleMark() }) {
                Icon(
                    if (f.marked == 1) Icons.Filled.Star else Icons.Filled.StarBorder,
                    contentDescription = stringResource(R.string.mark),
                    tint = if (f.marked == 1) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

/** 合集内展开的文件行（缩进 + 显示原文件名/书名与路径）。整行点击进入明细。 */
@Composable
private fun GroupFileRow(
    f: ScannedFileEntity,
    selected: Boolean,
    onToggleSelect: () -> Unit,
    onToggleMark: () -> Unit,
    onOpen: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onOpen() }
            .padding(start = 24.dp, end = 8.dp, top = 4.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Checkbox(checked = selected, onCheckedChange = { onToggleSelect() })
        Column(modifier = Modifier.weight(1f).padding(start = 4.dp)) {
            // 主标题：解析书名优先，缺则显示原文件名
            Text(
                f.title.ifBlank { f.fileName },
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                fontSize = 13.sp,
                fontWeight = MaterialTheme.typography.titleSmall.fontWeight
            )
            // 原文件名（与书名不同时显示）
            if (f.fileName.isNotBlank() && f.fileName != f.title) {
                Text(
                    stringResource(R.string.original_name_prefix) + f.fileName,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.outline
                )
            }
            val sub = buildList {
                if (f.author.isNotBlank()) add(f.author)
                add(FormatUtil.formatSize(f.fileSize))
                if (f.progress.isNotBlank()) add(f.progress)
                if (f.source.isNotBlank()) add(stringResource(R.string.source_label) + "：" + f.source)
            }.joinToString(" · ")
            if (sub.isNotBlank()) {
                Text(
                    sub,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        IconButton(onClick = onToggleMark) {
            Icon(
                if (f.marked == 1) Icons.Filled.Star else Icons.Filled.StarBorder,
                contentDescription = stringResource(R.string.mark),
                tint = if (f.marked == 1) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

/** 合集设置弹窗：文件数量区间 + 排除合集书名。 */
@Composable
private fun GroupSettingsDialog(
    initMin: Int,
    initMax: Int,
    initExclude: String,
    onDismiss: () -> Unit,
    onConfirm: (Int, Int, String) -> Unit
) {
    var minText by remember { mutableStateOf(if (initMin > 0) initMin.toString() else "") }
    var maxText by remember { mutableStateOf(if (initMax >= 0) initMax.toString() else "") }
    var excludeText by remember { mutableStateOf(initExclude) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.group_settings)) },
        text = {
            Column {
                Text(
                    stringResource(R.string.group_count_range_hint),
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(8.dp))
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedTextField(
                        value = minText,
                        onValueChange = { s -> minText = s.filter { it.isDigit() } },
                        label = { Text(stringResource(R.string.group_min)) },
                        singleLine = true,
                        modifier = Modifier.weight(1f)
                    )
                    Text("~")
                    OutlinedTextField(
                        value = maxText,
                        onValueChange = { s -> maxText = s.filter { it.isDigit() } },
                        label = { Text(stringResource(R.string.group_max)) },
                        singleLine = true,
                        modifier = Modifier.weight(1f)
                    )
                }
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = excludeText,
                    onValueChange = { excludeText = it },
                    label = { Text(stringResource(R.string.group_exclude)) },
                    placeholder = { Text(stringResource(R.string.group_exclude_hint)) },
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            AppButton(onClick = {
                val min = minText.toIntOrNull() ?: 0
                val max = maxText.toIntOrNull() ?: -1
                onConfirm(min, max, excludeText.trim())
            }) { Text(stringResource(R.string.confirm)) }
        },
        dismissButton = {
            AppOutlinedButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
        }
    )
}

/**
 * 分页导航条：用于 10w 级大库的分页浏览，交互对齐 PC 端。
 * - 每页条数：输入框（默认 100，范围 10~2000）填完点“应用”生效，不再提供预设按钮。
 * - 跳转：输入框填页码 + “跳转”按钮跳到指定页（对齐 PC 端“跳至页”）。
 * - 首页 / 上一页 / 下一页 / 末页 供快速翻页；越界自动禁用。
 * 当前页由 ViewModel 的 currentPage 状态驱动（真·页码分页）。
 */
@Composable
private fun PageNavBar(
    totalCount: Int,
    pageSize: Int,
    currentPage: Int,
    onPageSizeChange: (Int) -> Unit,
    onJumpToPage: (Int) -> Unit
) {
    val pageCount = ((totalCount + pageSize - 1) / pageSize.coerceAtLeast(1)).coerceAtLeast(1)
    // 当前页兜底夹在 [0, pageCount-1]，避免总数变化瞬间越界显示
    val page = currentPage.coerceIn(0, pageCount - 1)

    // 每页条数本地输入态：仅在“应用(✓)”时提交给 ViewModel（对齐 PC 端：填完再确认）
    var pageSizeText by remember(pageSize) { mutableStateOf((if (pageSize > 0) pageSize else 100).toString()) }
    // 跳页输入框默认显示当前页（1 基），用户直接覆盖输入；当前页变化时也跟随刷新
    var jumpText by remember(page) { mutableStateOf((page + 1).toString()) }
    val numKeyboard = KeyboardOptions(keyboardType = KeyboardType.Number)
    val tfShape = RoundedCornerShape(6.dp)

    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
    // 分两行布局：第1行翻页导航（居中），第2行每页/跳页设置（居中）。
    // 单行 9 个元素在手机窄屏（360dp）根本装不下，会被截断。
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        // 第一行：首页 / 上一页 / 页码 / 下一页 / 末页（居中）
        // 用 Unicode 符号代替中文：« ‹ › »，避免文字按钮在窄屏挤占水平空间、与页码信息错位
        // （contentDescription 仍用 stringResource 保留无障碍标签）
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally)
        ) {
            AppOutlinedButton(
                onClick = { onJumpToPage(0) },
                enabled = page > 0,
                modifier = Modifier.height(30.dp).width(36.dp),
                contentPadding = PaddingValues(horizontal = 0.dp, vertical = 2.dp)
            ) {
                Text(
                    text = "«",
                    fontSize = 16.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
            }
            AppOutlinedButton(
                onClick = { onJumpToPage((page - 1).coerceAtLeast(0)) },
                enabled = page > 0,
                modifier = Modifier.height(30.dp).width(36.dp),
                contentPadding = PaddingValues(horizontal = 0.dp, vertical = 2.dp)
            ) {
                Text(
                    text = "‹",
                    fontSize = 16.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
            }
            Text(
                stringResource(R.string.page_info, page + 1, pageCount, totalCount),
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 4.dp)
            )
            AppOutlinedButton(
                onClick = { onJumpToPage((page + 1).coerceAtMost(pageCount - 1)) },
                enabled = page < pageCount - 1,
                modifier = Modifier.height(30.dp).width(36.dp),
                contentPadding = PaddingValues(horizontal = 0.dp, vertical = 2.dp)
            ) {
                Text(
                    text = "›",
                    fontSize = 16.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
            }
            AppOutlinedButton(
                onClick = { onJumpToPage(pageCount - 1) },
                enabled = page < pageCount - 1,
                modifier = Modifier.height(30.dp).width(36.dp),
                contentPadding = PaddingValues(horizontal = 0.dp, vertical = 2.dp)
            ) {
                Text(
                    text = "»",
                    fontSize = 16.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
        // 第二行：每页条数 + 跳到指定页（居中）
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally)
        ) {
            Text(stringResource(R.string.page_size), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            // 用 BasicTextField 替代 OutlinedTextField：Material3 OutlinedTextField 有默认最小高度
            // (~56dp)，强制 height(30.dp) 会把内部输入区域压到几乎消失，导致点击没反应/软键盘弹不出。
            Box(
                modifier = Modifier
                    .width(64.dp)
                    .height(32.dp)
                    .border(1.dp, MaterialTheme.colorScheme.outline, tfShape)
                    .padding(horizontal = 6.dp, vertical = 4.dp),
                contentAlignment = Alignment.Center
            ) {
                BasicTextField(
                    value = pageSizeText,
                    onValueChange = { pageSizeText = it.filter { c -> c.isDigit() } },
                    singleLine = true,
                    keyboardOptions = numKeyboard,
                    textStyle = TextStyle(fontSize = 12.sp, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurface),
                    modifier = Modifier.fillMaxWidth()
                )
            }
            AppButton(
                onClick = {
                    val v = pageSizeText.toIntOrNull() ?: 100
                    val clamped = v.coerceIn(10, 2000)
                    pageSizeText = clamped.toString()
                    onPageSizeChange(clamped)
                },
                modifier = Modifier.height(30.dp),
                contentPadding = PaddingValues(horizontal = 3.dp, vertical = 0.dp)
            ) { Text("✓", fontSize = 13.sp) }
            Text("跳转", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Box(
                modifier = Modifier
                    .width(64.dp)
                    .height(32.dp)
                    .border(1.dp, MaterialTheme.colorScheme.outline, tfShape)
                    .padding(horizontal = 6.dp, vertical = 4.dp),
                contentAlignment = Alignment.Center
            ) {
                BasicTextField(
                    value = jumpText,
                    onValueChange = { jumpText = it.filter { c -> c.isDigit() } },
                    singleLine = true,
                    keyboardOptions = numKeyboard,
                    textStyle = TextStyle(fontSize = 12.sp, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurface),
                    modifier = Modifier.fillMaxWidth()
                )
            }
            AppButton(
                onClick = {
                    val p = jumpText.toIntOrNull()
                    if (p != null && p >= 1 && p <= pageCount) onJumpToPage(p - 1)
                },
                enabled = jumpText.isNotBlank(),
                modifier = Modifier.height(30.dp),
                contentPadding = PaddingValues(horizontal = 3.dp, vertical = 0.dp)
            ) { Text("✓", fontSize = 13.sp) }
        }
    }
}

private fun formatDate(ts: Long): String {
    return try {
        SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault()).format(Date(ts))
    } catch (_: Exception) {
        ""
    }
}

/**
 * 清理步骤指示器（Stepper）：扫描 → 合集模式 → 标记重复 → 确认勾选 → 删除。
 * 状态完全由现有 groupMode / checkedCount / duplicateProgress 推导，用于引导用户按顺序操作。
 */
private data class StepInfo(
    val index: Int,
    val label: String,
    val done: Boolean,
    val active: Boolean,
    val clickable: Boolean,
    val onClick: () -> Unit,
)

@Composable
private fun StepIndicator(
    groupMode: Boolean,
    checkedCount: Int,
    duplicateRunning: Boolean,
    onGoGroup: () -> Unit,
    onMarkDuplicates: () -> Unit,
    onDelete: () -> Unit,
) {
    val steps = listOf(
        StepInfo(
            index = 1,
            label = stringResource(R.string.step_scanned),
            done = true,
            active = false,
            clickable = false,
            onClick = {},
        ),
        StepInfo(
            index = 2,
            label = stringResource(R.string.group_mode),
            done = groupMode,
            active = !groupMode,
            clickable = !groupMode,
            onClick = onGoGroup,
        ),
        StepInfo(
            index = 3,
            label = stringResource(R.string.mark_duplicates),
            done = checkedCount > 0,
            active = groupMode && checkedCount == 0,
            clickable = groupMode && !duplicateRunning,
            onClick = onMarkDuplicates,
        ),
        StepInfo(
            index = 4,
            label = stringResource(R.string.step_confirm),
            done = false,
            active = checkedCount > 0,
            clickable = false,
            onClick = {},
        ),
        StepInfo(
            index = 5,
            label = stringResource(R.string.batch_delete_selected),
            done = false,
            active = checkedCount > 0,
            clickable = checkedCount > 0,
            onClick = onDelete,
        ),
    )

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        steps.forEachIndexed { idx, step ->
            if (idx > 0) {
                val prevDone = steps[idx - 1].done
                Spacer(
                    modifier = Modifier
                        .weight(1f)
                        .height(2.dp)
                        .background(if (prevDone) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant)
                )
            }
            StepNode(step = step)
        }
    }
}

@Composable
private fun StepNode(step: StepInfo) {
    val accent = MaterialTheme.colorScheme.primary
    val onAccent = MaterialTheme.colorScheme.onPrimary
    val outline = MaterialTheme.colorScheme.outline
    val onSurfaceVariant = MaterialTheme.colorScheme.onSurfaceVariant

    val circleColor = when {
        step.done -> accent
        step.active -> MaterialTheme.colorScheme.primaryContainer
        else -> MaterialTheme.colorScheme.surface
    }
    val ringColor = when {
        step.done || step.active -> accent
        else -> outline
    }
    val contentColor = when {
        step.done -> onAccent
        step.active -> MaterialTheme.colorScheme.onPrimaryContainer
        else -> onSurfaceVariant
    }
    val labelColor = when {
        step.done || step.active -> accent
        else -> onSurfaceVariant
    }

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .then(if (step.clickable) Modifier.clickable(onClick = step.onClick) else Modifier)
            .padding(2.dp)
    ) {
        Box(
            modifier = Modifier
                .size(26.dp)
                .background(circleColor, CircleShape)
                .border(1.5.dp, ringColor, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            if (step.done) {
                Icon(
                    imageVector = Icons.Filled.Check,
                    contentDescription = null,
                    tint = contentColor,
                    modifier = Modifier.size(16.dp)
                )
            } else {
                Text(
                    text = step.index.toString(),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = contentColor
                )
            }
        }
        Spacer(modifier = Modifier.height(2.dp))
        Text(
            text = step.label,
            fontSize = 10.sp,
            color = labelColor,
            maxLines = 1
        )
    }
}

/**
 * 紧凑筛选片：自绘以绕开 Material3 FilterChip 的 32dp 默认最小高度，
 * 把文字与边框的上下距离压到 2dp，但保证文字完整可见（不裁剪）。
 * 选中态：主题色填充 + 主题色描边 + 主题色文字；未选中：透明底 + 灰描边。
 */
@Composable
private fun CompactChip(
    selected: Boolean,
    onClick: () -> Unit,
    label: String,
    modifier: Modifier = Modifier
) {
    val bgColor = if (selected) MaterialTheme.colorScheme.primaryContainer else Color.Transparent
    val borderColor = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant
    val textColor = if (selected) MaterialTheme.colorScheme.onPrimaryContainer
    else MaterialTheme.colorScheme.onSurfaceVariant
    val shape = RoundedCornerShape(14.dp)
    Box(
        modifier = modifier
            .height(28.dp)
            .clip(shape)
            .background(bgColor)
            .border(1.dp, borderColor, shape)
            .clickable { onClick() }
            .padding(horizontal = 12.dp, vertical = 2.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(label, fontSize = 13.sp, color = textColor)
    }
}
