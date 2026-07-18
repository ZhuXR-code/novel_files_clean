package com.filescanner.app.ui.screens.library

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.filescanner.app.FileScannerApp
import com.filescanner.app.data.database.entity.ScannedFileEntity
import com.filescanner.app.data.database.entity.ScanRunEntity
import com.filescanner.app.data.model.NovelGroup
import com.filescanner.app.util.LogUtil
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

enum class FilterMode { ALL, MARKED }
enum class SortMode { TIME, NAME, SIZE }

/** 列表模式「当前页」的完整状态：本页数据 + 满足条件的总数 + 页码信息。 */
data class ListPageState(
    val items: List<ScannedFileEntity> = emptyList(),
    val total: Int = 0,
    val page: Int = 0,
    val pageSize: Int = 100,
    val loading: Boolean = true
)

/** 合集模式「当前页」的完整状态：本页分组 + 满足条件的分组总数 + 页码信息。 */
data class GroupPageState(
    val groups: List<NovelGroup> = emptyList(),
    val total: Int = 0,
    val page: Int = 0,
    val pageSize: Int = 100,
    val loading: Boolean = true
)

class LibraryViewModel(application: Application) : AndroidViewModel(application) {
    private val app = application as FileScannerApp
    private val repo = app.repository
    private val prefs = app.preferencesUtil

    /** 当前所在的文库（某次扫描）。null 表示正在浏览“文库列表”。 */
    private val _currentRunId = MutableStateFlow<Long?>(null)
    val currentRunId: StateFlow<Long?> = _currentRunId

    /** 文库（每次扫描）列表。 */
    val scanRuns: Flow<List<ScanRunEntity>> = repo.scanRuns

    private val _filter = MutableStateFlow(FilterMode.ALL)
    val filter: StateFlow<FilterMode> = _filter

    private val _sort = MutableStateFlow(SortMode.TIME)
    val sort: StateFlow<SortMode> = _sort

    private val _query = MutableStateFlow("")
    val query: StateFlow<String> = _query
    // 搜索加 300ms 防抖，避免每键都对 10w 级数据做 filter/sort
    private val _queryDebounced = _query.debounce(300).distinctUntilChanged()

    /** 每页条数（分页导航条用）：默认 100，范围 10~2000，由用户在导航条输入后应用。 */
    private val _pageSize = MutableStateFlow(100)
    val pageSize: StateFlow<Int> = _pageSize

    /** 当前页码（0 基）。翻页只改它；筛选/搜索/排序/每页条数/切换文库或模式时重置为 0。 */
    private val _currentPage = MutableStateFlow(0)
    val currentPage: StateFlow<Int> = _currentPage

    /** 每页条数 + 当前页 合成一个键，便于放进 5 参数 combine。 */
    private val _pageKey: Flow<Pair<Int, Int>> =
        combine(_pageSize, _currentPage) { ps, page -> ps to page }

    private val _selection = MutableStateFlow<Set<Long>>(emptySet())
    val selection: StateFlow<Set<Long>> = _selection

    private val _toast = MutableStateFlow<String?>(null)
    val toast: StateFlow<String?> = _toast

    // 合集计算（标记重复）进度：-1=空闲/完成，0~100=进行中
    private val _duplicateProgress = MutableStateFlow(-1)
    val duplicateProgress: StateFlow<Int> = _duplicateProgress

    // ===================== 合集模式 =====================
    private val _groupMode = MutableStateFlow(false)
    val groupMode: StateFlow<Boolean> = _groupMode

    // 合集筛选参数（初始化时从 DataStore 读取）
    private val _groupMinCount = MutableStateFlow(0)
    val groupMinCount: StateFlow<Int> = _groupMinCount
    private val _groupMaxCount = MutableStateFlow(-1)   // -1 = 不限
    val groupMaxCount: StateFlow<Int> = _groupMaxCount
    private val _groupExcludeNames = MutableStateFlow("")
    val groupExcludeNames: StateFlow<String> = _groupExcludeNames

    // 已展开的合集（书名）
    private val _expandedGroups = MutableStateFlow<Set<String>>(emptySet())
    val expandedGroups: StateFlow<Set<String>> = _expandedGroups

    // 已展开合集的文件缓存：书名 -> 文件列表（懒加载）
    private val _groupFiles = MutableStateFlow<Map<String, List<ScannedFileEntity>>>(emptyMap())
    val groupFiles: StateFlow<Map<String, List<ScannedFileEntity>>> = _groupFiles

    init {
        viewModelScope.launch {
            _groupMinCount.value = prefs.groupMinCount.first()
            _groupMaxCount.value = prefs.groupMaxCount.first()
            _groupExcludeNames.value = prefs.groupExcludeNames.first()
        }
    }

    /**
     * 列表模式「当前页」状态流（真·页码分页）：筛选/排序/搜索/每页条数/当前页 任一变化都重新查询。
     * 底层用 LIMIT/OFFSET 只查一页；count 与 page 均为 Room Flow，标记/删除等写操作后自动刷新。
     * 仅在进入某文库（runId 非空）时有数据，否则为空。
     */
    val listPageState: StateFlow<ListPageState> =
        combine(_filter, _sort, _queryDebounced, _currentRunId, _pageKey) { f, s, q, runId, key ->
            arrayOf(f, s, q, runId, key)
        }.flatMapLatest { arr ->
            val f = arr[0] as FilterMode
            val s = arr[1] as SortMode
            val q = arr[2] as String
            val runId = arr[3] as Long?
            val key = arr[4] as Pair<*, *>
            val ps = key.first as Int
            val page = key.second as Int
            if (runId == null) return@flatMapLatest flowOf(ListPageState(loading = false))
            combine(
                repo.filesCountFlow(f.name, q, runId),
                repo.filesPageFlow(f.name, q, s.name, runId, ps, page)
            ) { total, items ->
                val pageCount = ((total + ps - 1) / ps).coerceAtLeast(1)
                // 当前页越界（如删除后总数变少）→ 自动回退到最后一页
                if (page > pageCount - 1 && total > 0) _currentPage.value = pageCount - 1
                ListPageState(
                    items = items,
                    total = total,
                    page = page.coerceIn(0, pageCount - 1),
                    pageSize = ps,
                    loading = false
                )
            }
        }.flowOn(Dispatchers.IO)
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), ListPageState())

    /** 合集模式「当前页」状态流（真·页码分页）：区间/排除/搜索/每页条数/当前页 任一变化都重新查询。 */
    val groupPageState: StateFlow<GroupPageState> =
        combine(
            combine(_groupMinCount, _groupMaxCount, _groupExcludeNames, _queryDebounced) { min, max, exclude, q ->
                arrayOf(min, max, exclude, q)
            },
            _currentRunId,
            _pageKey
        ) { arr, runId, key -> Triple(arr, runId, key) }
            .flatMapLatest { (arr, runId, key) ->
                val min = arr[0] as Int
                val max = arr[1] as Int
                val exclude = (arr[2] as String).split(Regex("[,\n]+")).map { it.trim() }.filter { it.isNotEmpty() }
                val q = arr[3] as String
                val (ps, page) = key
                if (runId == null) return@flatMapLatest flowOf(GroupPageState(loading = false))
                combine(
                    repo.groupsCountFlow(min, max, exclude, q, runId),
                    repo.groupsPageFlow(min, max, exclude, q, runId, ps, page)
                ) { total, groups ->
                    val pageCount = ((total + ps - 1) / ps).coerceAtLeast(1)
                    if (page > pageCount - 1 && total > 0) _currentPage.value = pageCount - 1
                    GroupPageState(
                        groups = groups,
                        total = total,
                        page = page.coerceIn(0, pageCount - 1),
                        pageSize = ps,
                        loading = false
                    )
                }
            }.flowOn(Dispatchers.IO)
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), GroupPageState())

    fun setCurrentRunId(runId: Long?) {
        _currentRunId.value = runId
        _selection.value = emptySet()
        _currentPage.value = 0
    }

    fun setFilter(f: FilterMode) { _filter.value = f; _currentPage.value = 0 }
    fun setSort(s: SortMode) { _sort.value = s; _currentPage.value = 0 }
    fun setQuery(q: String) { _query.value = q; _currentPage.value = 0 }
    fun clearToast() { _toast.value = null }

    /** 设置每页条数（分页导航条）。变化后回到第 1 页。 */
    fun setPageSize(size: Int) { _pageSize.value = size.coerceAtLeast(1); _currentPage.value = 0 }

    /** 跳转到指定页（0 基）。翻页仅改页码，由 listPageState/groupPageState 自动查该页数据。 */
    fun goToPage(page: Int) { _currentPage.value = page.coerceAtLeast(0) }

    fun setGroupMode(enabled: Boolean) {
        _groupMode.value = enabled
        // 切换模式时清空展开与选择，避免两种视图选择混淆
        _expandedGroups.value = emptySet()
        _groupFiles.value = emptyMap()
        _selection.value = emptySet()
        _currentPage.value = 0
    }

    fun toggleGroupMode() = setGroupMode(!_groupMode.value)

    /** 保存合集筛选设置（数量区间 + 排除列表），并持久化。 */
    fun applyGroupFilter(minCount: Int, maxCount: Int, excludeNames: String) {
        _groupMinCount.value = minCount.coerceAtLeast(0)
        _groupMaxCount.value = maxCount
        _groupExcludeNames.value = excludeNames
        _expandedGroups.value = emptySet()
        _groupFiles.value = emptyMap()
        _currentPage.value = 0
        viewModelScope.launch(Dispatchers.IO) {
            prefs.setGroupFilter(minCount.coerceAtLeast(0), maxCount, excludeNames)
        }
    }

    /** 展开/折叠某合集；展开时懒加载其文件列表。 */
    fun toggleGroupExpand(title: String) {
        val cur = _expandedGroups.value.toMutableSet()
        if (cur.contains(title)) {
            cur.remove(title)
            _expandedGroups.value = cur
        } else {
            cur.add(title)
            _expandedGroups.value = cur
            if (!_groupFiles.value.containsKey(title)) {
                val runId = _currentRunId.value ?: return@toggleGroupExpand
                viewModelScope.launch(Dispatchers.IO) {
                    val files = repo.getFilesByTitle(runId, title)
                    _groupFiles.value = _groupFiles.value + (title to files)
                }
            }
        }
    }

    /** 合集内全选/取消全选（需先展开加载过文件）。 */
    fun toggleGroupSelectAll(title: String) {
        val files = _groupFiles.value[title] ?: return
        val ids = files.map { it.id }
        val cur = _selection.value.toMutableSet()
        val allSelected = ids.isNotEmpty() && ids.all { cur.contains(it) }
        if (allSelected) cur.removeAll(ids.toSet()) else cur.addAll(ids)
        _selection.value = cur
    }

    fun toggleSelect(id: Long) {
        val cur = _selection.value.toMutableSet()
        if (cur.contains(id)) cur.remove(id) else cur.add(id)
        _selection.value = cur
    }

    fun clearSelection() { _selection.value = emptySet() }

    /** 把当前选择交给删除流程（放入暂存单例），并清空本地选择，返回 id 列表。 */
    fun takeSelectionForDelete(): List<Long> {
        val ids = _selection.value.toList()
        _selection.value = emptySet()
        return ids
    }

    fun toggleMark(id: Long, current: Int) {
        viewModelScope.launch(Dispatchers.IO) {
            repo.setMarked(id, current != 1)
        }
    }

    suspend fun getById(id: Long): ScannedFileEntity? = repo.getById(id)

    fun markDuplicatesByName() {
        val runId = _currentRunId.value ?: run { _toast.value = "请先进入某个文库"; return }
        viewModelScope.launch(Dispatchers.IO) {
            val n = repo.markDuplicatesByName(runId)
            _toast.value = if (n > 0) "已按书名/作者相同标记 $n 个文件" else "未发现同名/同作者的重复文件"
        }
    }

    fun clearMarked() {
        val runId = _currentRunId.value ?: run { _toast.value = "请先进入某个文库"; return }
        viewModelScope.launch(Dispatchers.IO) {
            repo.clearMarked(runId)
            _toast.value = "已清除本文库全部标记"
        }
    }

    /**
     * 合集模式“标记重复”：复刻 PC 端 /groups/select-duplicates，
     * 计算应勾选（待删）的重复文件 id，并入当前选择，由底部“删除选中”执行删除。
     */
    fun selectDuplicates() {
        val runId = _currentRunId.value ?: run { _toast.value = "请先进入某个文库"; return }
        if (_duplicateProgress.value >= 0) {
            _toast.value = "合集计算进行中，请稍候..."
            return
        }
        viewModelScope.launch(Dispatchers.IO) {
            _duplicateProgress.value = 0
            LogUtil.i("LibVM", "selectDuplicates 开始合集计算 run=$runId")
            try {
                val rows = repo.getDuplicateRows(runId)
                val total = rows.size
                LogUtil.i("LibVM", "selectDuplicates 载入待判定行 $total 条")
                if (total == 0) {
                    _toast.value = "未发现同名/同作者的重复文件"
                    return@launch
                }
                // 分块计算（每 2000 行推进一次进度），避免 10w+ 数据下长时间无反馈
                val groupedAll = LinkedHashMap<Pair<String, String>, MutableList<Triple<Long, String, Long>>>()
                val groupedNumeric = LinkedHashMap<Pair<String, String>, MutableList<Triple<Long, Int, Long>>>()
                val completionKeywords = listOf("完结", "番外", "完本", "全本")
                val result = mutableListOf<Long>()
                val chunk = 2000
                for (i in rows.indices) {
                    val r = rows[i]
                    val author = r.author.trim()
                    if (author.isEmpty()) continue
                    val key = r.title.trim() to author
                    val progress = r.progress.trim()
                    groupedAll.getOrPut(key) { mutableListOf() }.add(Triple(r.id, progress, r.fileSize))
                    if (progress.isNotEmpty() && progress.all { it.isDigit() }) {
                        groupedNumeric.getOrPut(key) { mutableListOf() }.add(Triple(r.id, progress.toInt(), r.fileSize))
                    }
                    if (i % chunk == chunk - 1 || i == rows.lastIndex) {
                        _duplicateProgress.value = ((i + 1) * 100 / total).coerceIn(0, 100)
                    }
                }
                for ((key, allEntries) in groupedAll) {
                    val numeric = groupedNumeric[key] ?: continue
                    if (numeric.size < 2) continue
                    val hasCompletion = allEntries.any { (_, p, _) ->
                        completionKeywords.any { kw -> p.contains(kw) }
                    }
                    val checked = if (hasCompletion) {
                        numeric.map { it.first }
                    } else {
                        val sorted = numeric.sortedByDescending { it.second }
                        sorted.drop(1).map { it.first }
                    }
                    if (checked.isNotEmpty()) {
                        val maxItem = allEntries.maxByOrNull { it.third } ?: continue
                        val adjusted = checked.toMutableList()
                        if (maxItem.first in adjusted) adjusted.remove(maxItem.first)
                        result.addAll(adjusted)
                    }
                }
                LogUtil.i("LibVM", "selectDuplicates 合集计算完成，应勾选 ${result.size} 个")
                if (result.isEmpty()) {
                    _toast.value = "未找到符合条件的重复文件（同作者 + 纯数字进度 + 多条记录）"
                    return@launch
                }
                val cur = _selection.value.toMutableSet()
                val added = result.count { !cur.contains(it) }
                cur.addAll(result)
                _selection.value = cur
                _toast.value = "已标记重复 $added 个文件（共应勾选 ${result.size} 个）"
            } catch (e: Exception) {
                LogUtil.e("LibVM", "selectDuplicates 失败: ${e.message}")
                _toast.value = "合集计算失败：${e.message}"
            } finally {
                _duplicateProgress.value = -1
            }
        }
    }


    /** 删除整个文库（及其全部文件）。 */
    fun deleteRun(runId: Long) {
        viewModelScope.launch(Dispatchers.IO) {
            repo.deleteScanRun(runId)
            if (_currentRunId.value == runId) _currentRunId.value = null
            _toast.value = "已删除文库"
        }
    }
}
