package com.filescanner.app.ui.screens.library

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.filescanner.app.FileScannerApp
import com.filescanner.app.data.database.entity.ScannedFileEntity
import com.filescanner.app.data.database.entity.ScanRunEntity
import com.filescanner.app.data.database.entity.DuplicateRow
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
import kotlinx.coroutines.runBlocking

enum class FilterMode { ALL, CHECKED, UNCHECKED, MARKED, UNMARKED }
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

    /** 当前文库【已勾选】(checked) 文件总数，供底部批量操作栏显隐与计数。 */
    val checkedCount: StateFlow<Int> = _currentRunId.flatMapLatest { runId ->
        if (runId == null) flowOf(0) else repo.checkedCountFlow(runId)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), 0)

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
            combine(_groupMinCount, _groupMaxCount, _groupExcludeNames, _queryDebounced, _filter) { min, max, exclude, q, f ->
                arrayOf(min, max, exclude, q, f)
            },
            _currentRunId,
            _pageKey
        ) { arr, runId, key -> Triple(arr, runId, key) }
            .flatMapLatest { (arr, runId, key) ->
                val min = arr[0] as Int
                val max = arr[1] as Int
                val exclude = (arr[2] as String).split(Regex("[,\n]+")).map { it.trim() }.filter { it.isNotEmpty() }
                val q = arr[3] as String
                val f = arr[4] as FilterMode
                val filterName = f.name
                val (ps, page) = key
                if (runId == null) return@flatMapLatest flowOf(GroupPageState(loading = false))
                combine(
                    repo.groupsCountFlow(min, max, exclude, q, runId, filterName),
                    repo.groupsPageFlow(min, max, exclude, q, runId, ps, page, filterName)
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
        _expandedGroups.value = emptySet()
        _groupFiles.value = emptyMap()
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
                val markedArg = when (_filter.value) {
                    FilterMode.ALL -> null
                    FilterMode.MARKED -> 1
                    FilterMode.UNMARKED -> 0
                    else -> null
                }
                val checkedArg = when (_filter.value) {
                    FilterMode.CHECKED -> 1
                    FilterMode.UNCHECKED -> 0
                    else -> null
                }
                viewModelScope.launch(Dispatchers.IO) {
                    val files = repo.getFilesByTitle(runId, title, markedArg, checkedArg)
                    _groupFiles.value = _groupFiles.value + (title to files)
                }
            }
        }
    }

    /** 合集内全选/取消全选（需先展开加载过文件）。 */
    fun toggleGroupSelectAll(title: String) {
        val files = _groupFiles.value[title] ?: return
        val ids = files.map { it.id }
        val allChecked = files.isNotEmpty() && files.all { it.checked == 1 }
        val target = !allChecked
        viewModelScope.launch(Dispatchers.IO) {
            repo.setCheckedForIds(ids, target)
        }
    }

    /** 勾选/取消勾选单个文件（持久化到 checked 字段，与 marked 星标无关）。 */
    fun toggleSelect(id: Long, currentChecked: Int) {
        viewModelScope.launch(Dispatchers.IO) {
            repo.setChecked(id, currentChecked != 1)
        }
    }

    /** 清空当前文库的勾选（取消批量删除选择）。 */
    fun clearChecked() {
        val runId = _currentRunId.value ?: return
        viewModelScope.launch(Dispatchers.IO) { repo.clearChecked(runId) }
    }

    /** 取出当前文库所有【已勾选】(checked) 的文件 id，交给删除流程（暂存单例）。 */
    fun takeSelectionForDelete(): List<Long> {
        val runId = _currentRunId.value ?: return emptyList()
        return runBlocking { runCatching { repo.getCheckedIds(runId) }.getOrDefault(emptyList()) }
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
     * 合集模式“标记重复”：复用 PC 端 /api/groups/select-duplicates 的五则判定
     * （算法在 FileRepository.selectDuplicateIds，与 backend/dup_logic.py 完全一致）。
     * 计算符合要求的重复文件 id，直接持久化写入 checked=1（即“勾选”），由底部
     * “批量删除选中”执行删除。与 marked（星标）完全无关。
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
                // 计算重复并直接持久化写入 checked=1（标记重复=勾选），仅新增、不清空其它已勾选
                val ids = repo.selectDuplicateIds(runId)
                LogUtil.i("LibVM", "selectDuplicates 合集计算完成，已勾选 ${ids.size} 个")
                if (ids.isEmpty()) {
                    _toast.value = "未找到符合条件的重复文件"
                    return@launch
                }
                _toast.value = "已标记重复 ${ids.size} 个文件（已勾选），可在筛选“已勾选”后批量删除选中"
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
