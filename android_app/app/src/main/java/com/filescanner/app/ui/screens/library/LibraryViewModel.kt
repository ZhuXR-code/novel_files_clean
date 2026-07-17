package com.filescanner.app.ui.screens.library

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.filescanner.app.FileScannerApp
import com.filescanner.app.data.database.entity.ScannedFileEntity
import com.filescanner.app.data.database.entity.ScanRunEntity
import com.filescanner.app.data.model.NovelGroup
import androidx.paging.PagingData
import androidx.paging.cachedIn
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

enum class FilterMode { ALL, MARKED }
enum class SortMode { TIME, NAME, SIZE }

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

    /** 每页条数（分页导航条用）：默认 100，可选 100/500/2000。 */
    private val _pageSize = MutableStateFlow(100)
    val pageSize: StateFlow<Int> = _pageSize

    /** 当前文库的总数（用于计算总页数）。仅当前文库非空时有效。 */
    val totalCount: Flow<Int> = _currentRunId.flatMapLatest { runId ->
        if (runId == null) flowOf(0) else repo.countByRun(runId)
    }.flowOn(Dispatchers.IO)

    private val _selection = MutableStateFlow<Set<Long>>(emptySet())
    val selection: StateFlow<Set<Long>> = _selection

    private val _toast = MutableStateFlow<String?>(null)
    val toast: StateFlow<String?> = _toast

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
     * 分页列表：筛选/排序/搜索任一变化都重建 Pager，DUPLICATES 过滤所需的重复哈希集合
     * 只在切到该筛选时取一次（而非每页/每键重算）。底层由 Room PagingSource 分批加载。
     * 仅在进入某文库（runId 非空）时加载，否则为空。
     */
    val pagedFiles: Flow<PagingData<ScannedFileEntity>> =
        combine(_filter, _sort, _queryDebounced, _currentRunId, _pageSize) { f, s, q, runId, ps ->
            arrayOf(f, s, q, runId, ps)
        }.flatMapLatest { arr ->
            val f = arr[0] as FilterMode
            val s = arr[1] as SortMode
            val q = arr[2] as String
            val runId = arr[3] as Long?
            val ps = arr[4] as Int
            if (runId == null) return@flatMapLatest flowOf(PagingData.empty())
            repo.pagedFiles(f.name, q, s.name, runId, ps)
        }.flowOn(Dispatchers.IO)

    /** 合集模式分页：数量区间/排除/搜索任一变化都重建 Pager。仅加载当前文库。 */
    val pagedGroups: Flow<PagingData<NovelGroup>> =
        _pageSize.flatMapLatest { ps ->
            combine(_groupMinCount, _groupMaxCount, _groupExcludeNames, _queryDebounced, _currentRunId) { min, max, exclude, q, runId ->
                arrayOf(min, max, exclude, q, runId)
            }.flatMapLatest { arr ->
                val min = arr[0] as Int
                val max = arr[1] as Int
                val exclude = (arr[2] as String).split(Regex("[,\n]+")).map { it.trim() }.filter { it.isNotEmpty() }
                val q = arr[3] as String
                val runId = arr[4] as Long?
                if (runId == null) return@flatMapLatest flowOf(PagingData.empty())
                repo.pagedGroups(min, max, exclude, q, runId, ps)
            }.flowOn(Dispatchers.IO)
        }.cachedIn(viewModelScope)

    fun setCurrentRunId(runId: Long?) {
        _currentRunId.value = runId
        _selection.value = emptySet()
    }

    fun setFilter(f: FilterMode) { _filter.value = f }
    fun setSort(s: SortMode) { _sort.value = s }
    fun setQuery(q: String) { _query.value = q }
    fun clearToast() { _toast.value = null }

    /** 设置每页条数（分页导航条）。变化会重建 Pager，列表回到顶部。 */
    fun setPageSize(size: Int) { _pageSize.value = size.coerceAtLeast(1) }

    fun setGroupMode(enabled: Boolean) {
        _groupMode.value = enabled
        // 切换模式时清空展开与选择，避免两种视图选择混淆
        _expandedGroups.value = emptySet()
        _groupFiles.value = emptyMap()
        _selection.value = emptySet()
    }

    fun toggleGroupMode() = setGroupMode(!_groupMode.value)

    /** 保存合集筛选设置（数量区间 + 排除列表），并持久化。 */
    fun applyGroupFilter(minCount: Int, maxCount: Int, excludeNames: String) {
        _groupMinCount.value = minCount.coerceAtLeast(0)
        _groupMaxCount.value = maxCount
        _groupExcludeNames.value = excludeNames
        _expandedGroups.value = emptySet()
        _groupFiles.value = emptyMap()
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
        viewModelScope.launch(Dispatchers.IO) {
            val ids = repo.selectDuplicateIds(runId)
            if (ids.isEmpty()) {
                _toast.value = "未找到符合条件的重复文件（同作者 + 纯数字进度 + 多条记录）"
                return@launch
            }
            val cur = _selection.value.toMutableSet()
            val added = ids.count { !cur.contains(it) }
            cur.addAll(ids)
            _selection.value = cur
            _toast.value = "已标记重复 $added 个文件（共应勾选 ${ids.size} 个）"
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
