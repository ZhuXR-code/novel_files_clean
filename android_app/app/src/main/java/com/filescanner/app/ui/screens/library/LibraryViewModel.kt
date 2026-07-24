package com.filescanner.app.ui.screens.library

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.filescanner.app.FileScannerApp
import com.filescanner.app.data.database.entity.ScannedFileEntity
import com.filescanner.app.data.database.entity.ScanRunEntity
import com.filescanner.app.data.database.entity.DuplicateRow
import com.filescanner.app.data.model.NovelGroup
import com.filescanner.app.util.LibraryLogic
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

enum class FilterMode { ALL, CHECKED, UNCHECKED, MARKED, UNMARKED, HAS_CHECKED }
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

    /**
     * 重查信号：标记/勾选/删除等写库操作不会让 Room Flow 自动重发当前页，
     * 通过自增该值触发 listPageState / groupPageState 重新查询，使界面即时刷新。
     */
    private val _reloadSignal = MutableStateFlow(0L)

    /** 每页条数 + 当前页 合成一个键，便于放进 5 参数 combine。
     *  额外并入 _reloadSignal：写库操作（清标记/清勾选/删除）后自增它，
     *  即可让 listPageState / groupPageState 都重新查询当前页，使界面即时刷新。 */
    private val _pageKey: Flow<Pair<Int, Int>> =
        combine(_pageSize, _currentPage, _reloadSignal) { ps, page, sig -> ps to page }

    /** 当前文库【已勾选】(checked) 文件总数，供底部批量操作栏显隐与计数。 */
    val checkedCount: StateFlow<Int> = _currentRunId.flatMapLatest { runId ->
        if (runId == null) flowOf(0) else repo.checkedCountFlow(runId)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), 0)

    private val _toast = MutableStateFlow<String?>(null)
    val toast: StateFlow<String?> = _toast

    // 合集计算（勾选重复）进度：-1=空闲/完成，0~100=进行中
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

    // 各合集已展开文件列表对应的筛选条件：书名 -> FilterMode。
    // 用于判断缓存是否过期——筛选变化时已展开合集需重载，否则停留在旧筛选结果
    // （例如 CHECKED 下展开只加载了 2 个已勾选文件，切到 ALL 后若不重载仍只显示这 2 个）。
    private val _groupFilesFilter = MutableStateFlow<Map<String, FilterMode>>(emptyMap())

    // 各合集已勾选文件数（书名 -> 已勾选数），供合集头部三态复选框显示「部分勾选(-)」状态。
    // 初始从 groupPageState 的聚合字段 seeded，勾选/取消时乐观更新，避免 RawQuery 不观测导致的状态陈旧。
    private val _groupCheckedCounts = MutableStateFlow<Map<String, Int>>(emptyMap())
    val groupCheckedCounts: StateFlow<Map<String, Int>> = _groupCheckedCounts

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
                val pageCount = LibraryLogic.computePageCount(total, ps)
                // 当前页越界（如删除后总数变少）→ 自动回退到最后一页
                if (page > pageCount - 1 && total > 0) _currentPage.value = pageCount - 1
                ListPageState(
                    items = items,
                    total = total,
                    page = LibraryLogic.adjustPage(page, pageCount),
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
                val exclude = LibraryLogic.parseExcludeNames(arr[2] as String)
                val q = arr[3] as String
                val f = arr[4] as FilterMode
                val filterName = f.name
                val (ps, page) = key
                if (runId == null) return@flatMapLatest flowOf(GroupPageState(loading = false))
                combine(
                    repo.groupsCountFlow(min, max, exclude, q, runId, filterName),
                    repo.groupsPageFlow(min, max, exclude, q, runId, ps, page, filterName)
                ) { total, groups ->
                    val pageCount = LibraryLogic.computePageCount(total, ps)
                    if (page > pageCount - 1 && total > 0) _currentPage.value = pageCount - 1
                    GroupPageState(
                        groups = groups,
                        total = total,
                        page = LibraryLogic.adjustPage(page, pageCount),
                        pageSize = ps,
                        loading = false
                    )
                }
            }.flowOn(Dispatchers.IO)
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), GroupPageState())

    // groupPageState 在本 init 块之前已声明初始化，此处再订阅它刷新各合集头部已勾选数状态。
    init {
        // 合集列表每页加载时，用数据库聚合的已勾选数刷新各合集头部状态（重置为真实值）
        viewModelScope.launch {
            groupPageState.collect { st ->
                if (st.groups.isNotEmpty()) {
                    _groupCheckedCounts.value = st.groups.associate { it.title to it.checkedCount }
                }
            }
        }
    }

    fun setCurrentRunId(runId: Long?) {
        _currentRunId.value = runId
        _currentPage.value = 0
    }

    fun setFilter(f: FilterMode) { _filter.value = f; _currentPage.value = 0; reloadExpandedGroups() }
    fun setSort(s: SortMode) { LogUtil.i("LibVM", "setSort $s"); _sort.value = s; _currentPage.value = 0 }
    fun setQuery(q: String) { _query.value = q; _currentPage.value = 0 }
    fun clearToast() { _toast.value = null }

    /** 设置每页条数（分页导航条）。变化后回到第 1 页。 */
    fun setPageSize(size: Int) { _pageSize.value = size.coerceAtLeast(1); _currentPage.value = 0 }

    /** 跳转到指定页（0 基）。翻页仅改页码，由 listPageState/groupPageState 自动查该页数据。 */
    fun goToPage(page: Int) { _currentPage.value = page.coerceAtLeast(0) }

    fun setGroupMode(enabled: Boolean) {
        _groupMode.value = enabled
        // 「含已勾选」是合集级筛选，切回列表模式时无意义，回落到全部
        if (!enabled && _filter.value == FilterMode.HAS_CHECKED) _filter.value = FilterMode.ALL
        _expandedGroups.value = emptySet()
        _groupFiles.value = emptyMap()
        _groupFilesFilter.value = emptyMap()
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
        _groupFilesFilter.value = emptyMap()
        _currentPage.value = 0
        viewModelScope.launch(Dispatchers.IO) {
            prefs.setGroupFilter(minCount.coerceAtLeast(0), maxCount, excludeNames)
        }
    }

    /** 当前筛选条件对应的 marked/checked 查询参数（与展开合集加载文件时一致）。 */
    private fun currentFilterArgs(): Pair<Int?, Int?> {
        val markedArg = when (_filter.value) {
            FilterMode.MARKED -> 1
            FilterMode.UNMARKED -> 0
            else -> null
        }
        val checkedArg = when (_filter.value) {
            FilterMode.CHECKED -> 1
            FilterMode.UNCHECKED -> 0
            else -> null
        }
        return markedArg to checkedArg
    }

    /**
     * 筛选条件变化时，重新加载所有已展开合集的文件列表。
     * 否则缓存会停留在旧筛选结果（例如 CHECKED 下展开只加载了已勾选文件，
     * 切到 ALL 后仍只显示那些已勾选文件，而合集头部总数却显示全部）。
     */
    private fun reloadExpandedGroups() {
        val runId = _currentRunId.value ?: return
        val titles = _expandedGroups.value
        if (titles.isEmpty()) return
        val (markedArg, checkedArg) = currentFilterArgs()
        viewModelScope.launch(Dispatchers.IO) {
            val loaded = titles.associateWith { title ->
                repo.getFilesByTitle(runId, title, markedArg, checkedArg)
            }
            val newFilterMap = _groupFilesFilter.value.toMutableMap().apply {
                titles.forEach { this[it] = _filter.value }
            }
            _groupFiles.value = _groupFiles.value.toMutableMap().apply { putAll(loaded) }
            _groupFilesFilter.value = newFilterMap
        }
    }

    /** 展开/折叠某合集；展开时懒加载其文件列表（按当前筛选条件）。 */
    fun toggleGroupExpand(title: String) {
        val cur = _expandedGroups.value.toMutableSet()
        if (cur.contains(title)) {
            cur.remove(title)
            _expandedGroups.value = cur
        } else {
            cur.add(title)
            _expandedGroups.value = cur
            // 未加载过，或加载时使用的筛选条件与当前不一致，均重新查询（避免停留在旧筛选结果）
            if (!_groupFiles.value.containsKey(title) || _groupFilesFilter.value[title] != _filter.value) {
                val runId = _currentRunId.value ?: return@toggleGroupExpand
                val (markedArg, checkedArg) = currentFilterArgs()
                viewModelScope.launch(Dispatchers.IO) {
                    val files = repo.getFilesByTitle(runId, title, markedArg, checkedArg)
                    _groupFiles.value = _groupFiles.value + (title to files)
                    _groupFilesFilter.value = _groupFilesFilter.value + (title to _filter.value)
                }
            }
        }
    }

    /** 合集内全选/取消全选（需先展开加载过文件）。 */
    fun toggleGroupSelectAll(title: String) {
        val files = _groupFiles.value[title] ?: return
        val ids = files.map { it.id }
        val allChecked = files.isNotEmpty() && files.all { it.checked == 1 }
        val target = if (allChecked) 0 else 1
        val currentChecked = files.count { it.checked == 1 }
        val delta = if (target == 1) (files.size - currentChecked) else -currentChecked
        viewModelScope.launch(Dispatchers.IO) {
            repo.setCheckedForIds(ids, target == 1)
        }
        // 同步翻转快照，使组内各文件复选框与顶部三态复选框立即刷新
        _groupFiles.value = _groupFiles.value.toMutableMap().apply {
            this[title] = files.map { it.copy(checked = target) }
        }
        // 同步合集头部勾选计数（决定三态复选框是否显示「-」）
        bumpGroupCheckedCount(title, delta)
    }

    /** 调整某合集的已勾选计数（乐观更新），供合集头部三态复选框判断部分勾选状态。 */
    private fun bumpGroupCheckedCount(title: String, delta: Int) {
        val cur = _groupCheckedCounts.value.toMutableMap()
        cur[title] = (cur[title] ?: 0) + delta
        _groupCheckedCounts.value = cur
    }

    /**
     * 合集模式里 _groupFiles 是一次性快照，写库后不会自动刷新。
     * 这里同步翻转内存快照中该文件的 checked，让 UI 立即反映勾选变化
     * （仅更新所属合集的列表，避免对全部展开合集做全量 mapValues 重建）。
     */
    private fun syncGroupFileChecked(title: String, id: Long, newChecked: Int) {
        val cur = _groupFiles.value
        val files = cur[title] ?: return
        _groupFiles.value = cur.toMutableMap().apply {
            this[title] = files.map { if (it.id == id) it.copy(checked = newChecked) else it }
        }
    }

    /** 同上，针对 marked 星标的乐观更新。内部定位所属合集，仅更新该合集。 */
    private fun syncGroupFileMarked(id: Long, newMarked: Int) {
        val cur = _groupFiles.value
        if (cur.isEmpty()) return
        val entry = cur.entries.firstOrNull { it.value.any { f -> f.id == id } } ?: return
        _groupFiles.value = cur.toMutableMap().apply {
            this[entry.key] = entry.value.map { if (it.id == id) it.copy(marked = newMarked) else it }
        }
    }

    /** 勾选/取消勾选单个文件（持久化到 checked 字段，与 marked 星标无关）。 */
    fun toggleSelect(id: Long, currentChecked: Int) {
        val newChecked = if (currentChecked != 1) 1 else 0
        viewModelScope.launch(Dispatchers.IO) {
            repo.setChecked(id, newChecked == 1)
        }
        // 先定位 id 所属合集（用于局部更新该合集快照与勾选计数，避免全量 mapValues 重建）
        val title = _groupFiles.value.entries.firstOrNull { it.value.any { f -> f.id == id } }?.key
        if (title != null) {
            syncGroupFileChecked(title, id, newChecked)
            bumpGroupCheckedCount(title, if (newChecked == 1) 1 else -1)
        }
    }

    /** 清空当前文库的勾选（取消批量删除选择）。 */
    fun clearChecked() {
        val runId = _currentRunId.value ?: return
        viewModelScope.launch(Dispatchers.IO) {
            repo.clearChecked(runId)
            // 同时刷新内存快照，否则界面勾选不会立即消失
            _groupFiles.value = _groupFiles.value.mapValues { (_, list) -> list.map { it.copy(checked = 0) } }
            // 强制分页流重查，使列表/合集模式立即同步（Room Flow 不会自动重发当前页）
            _reloadSignal.value += 1
        }
    }

    /** 取出当前文库所有【已勾选】(checked) 的文件 id，交给删除流程（暂存单例）。 */
    suspend fun takeSelectionForDelete(): List<Long> {
        val runId = _currentRunId.value ?: return emptyList()
        return runCatching { repo.getCheckedIds(runId) }.getOrDefault(emptyList())
    }

    fun toggleMark(id: Long, current: Int) {
        LogUtil.i("LibVM", "toggleMark id=$id current=$current")
        val newMarked = if (current != 1) 1 else 0
        viewModelScope.launch(Dispatchers.IO) {
            repo.setMarked(id, newMarked == 1)
        }
        syncGroupFileMarked(id, newMarked)
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
            // 同时刷新内存快照，否则界面星标不会立即消失（snap 仍保留 marked=1）
            _groupFiles.value = _groupFiles.value.mapValues { (_, list) -> list.map { it.copy(marked = 0) } }
            // 强制分页流重查，使列表/合集模式立即同步（Room Flow 不会自动重发当前页）
            _reloadSignal.value += 1
            _toast.value = "已清除本文库全部标记"
        }
    }

    /**
     * 合集模式“勾选重复”：复用 PC 端 /api/groups/select-duplicates 的五则判定
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
                // 计算重复并直接持久化写入 checked=1（勾选重复=勾选），仅新增、不清空其它已勾选
                val ids = repo.selectDuplicateIds(runId)
                LogUtil.i("LibVM", "selectDuplicates 合集计算完成，已勾选 ${ids.size} 个")

                // 同步更新内存快照并触发分页流重查，使列表/合集模式立即显示勾选
                if (ids.isNotEmpty()) {
                    val idSet = ids.toSet()
                    _groupFiles.value = _groupFiles.value.mapValues { (_, list) ->
                        list.map { if (it.id in idSet) it.copy(checked = 1) else it }
                    }
                    _reloadSignal.value += 1
                }

                if (ids.isEmpty()) {
                    _toast.value = "未找到符合条件的重复文件"
                    return@launch
                }
                _toast.value = "已勾选重复 ${ids.size} 个文件（已勾选），可在筛选“已勾选”后批量删除选中"
            } catch (e: Exception) {
                LogUtil.e("LibVM", "selectDuplicates 失败: ${e.message}")
                _toast.value = "合集计算失败：${e.message}"
            } finally {
                _duplicateProgress.value = -1
            }
        }
    }

    /** 删除文库：删除文库及其书籍的数据库记录，但保留手机上的真实源文件。 */
    fun deleteRun(runId: Long) {
        viewModelScope.launch(Dispatchers.IO) {
            repo.deleteScanRun(runId)
            if (_currentRunId.value == runId) _currentRunId.value = null
            _toast.value = "已删除文库及其书籍记录（源文件已保留）"
        }
    }
}
