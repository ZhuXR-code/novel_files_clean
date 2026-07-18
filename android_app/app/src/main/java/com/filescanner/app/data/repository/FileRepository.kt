package com.filescanner.app.data.repository

import com.filescanner.app.data.database.dao.ScannedFileDao
import com.filescanner.app.data.database.dao.ScanRunDao
import com.filescanner.app.data.database.dao.KeywordReplaceDao
import com.filescanner.app.data.database.entity.ScannedFileEntity
import com.filescanner.app.data.database.entity.ScanRunEntity
import com.filescanner.app.data.database.entity.KeywordReplaceRuleEntity
import com.filescanner.app.data.database.entity.DuplicateRow
import com.filescanner.app.data.model.NovelGroup
import com.filescanner.app.util.ExportService
import com.filescanner.app.util.LogUtil
import androidx.paging.Pager
import androidx.paging.PagingConfig
import androidx.paging.PagingData
import androidx.paging.PagingSource
import androidx.paging.PagingState
import androidx.sqlite.db.SimpleSQLiteQuery
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf

class FileRepository(
    private val dao: ScannedFileDao,
    private val runDao: ScanRunDao,
    private val keywordDao: KeywordReplaceDao
) {
    /** 首页统计所需的计数流，直接走 COUNT(*)，不加载全表。 */
    val totalCount: Flow<Int> = dao.countFlow()
    val markedCount: Flow<Int> = dao.countMarkedFlow()

    /** 文库（每次扫描）列表流。 */
    val scanRuns: Flow<List<ScanRunEntity>> = runDao.getAllRuns()

    // ===================== 文库（scan_run）管理 =====================
    suspend fun getScanRun(id: Long): ScanRunEntity? = runDao.getById(id)

    /** 开始一次扫描前调用：新建文库记录，返回其 id，供文件关联。 */
    suspend fun createScanRun(
        name: String,
        folderUri: String,
        folderName: String,
        fileTypes: String
    ): Long = runDao.insert(
        ScanRunEntity(
            name = name,
            folderUri = folderUri,
            folderName = folderName,
            fileTypes = fileTypes
        )
    )

    /** 扫描完成后回写该文库的文件数。 */
    suspend fun setRunFileCount(runId: Long, count: Int) = runDao.setFileCount(runId, count)

    /** 删除整个文库及其全部文件。 */
    suspend fun deleteScanRun(runId: Long) {
        dao.deleteByRunId(runId)
        runDao.deleteById(runId)
    }

    suspend fun getById(id: Long): ScannedFileEntity? = dao.getById(id)
    suspend fun getByIds(ids: List<Long>): List<ScannedFileEntity> = dao.getByIds(ids)
    suspend fun getMarked(): List<ScannedFileEntity> = dao.getMarked()
    /** 某文库文件总数，供分页导航条计算总页数。 */
    fun countByRun(runId: Long): Flow<Int> = dao.countByRunFlow(runId)
    suspend fun count(): Int = 0 // 已改用 totalCount 流；保留以兼容潜在调用
    suspend fun countMarked(): Int = 0

    suspend fun setMarked(id: Long, marked: Boolean) {
        dao.setMarked(id, if (marked) 1 else 0)
    }

    suspend fun clearMarked(runId: Long) {
        LogUtil.i("Repo", "clearMarked 开始清除 run=$runId")
        dao.clearMarked(runId)
        LogUtil.i("Repo", "clearMarked 完成清除 run=$runId")
    }

    suspend fun insertAll(files: List<ScannedFileEntity>) {
        val n = files.size
        LogUtil.i("Repo", "insertAll 开始写入 $n 条 (run=${files.firstOrNull()?.scanRunId})")
        dao.insertAll(files)
        LogUtil.i("Repo", "insertAll 完成写入 $n 条")
    }

    suspend fun deleteByIds(ids: List<Long>) {
        if (ids.isNotEmpty()) {
            LogUtil.i("Repo", "deleteByIds 开始删除 ${ids.size} 条")
            dao.deleteByIds(ids)
            LogUtil.i("Repo", "deleteByIds 完成删除 ${ids.size} 条")
        }
    }

    suspend fun deleteAll() = dao.deleteAll()

    // ===================== 关键词替换规则 =====================
    /** 某作用域全部规则流（含禁用），供设置页展示。 */
    fun getRulesFlow(scope: String): Flow<List<KeywordReplaceRuleEntity>> =
        keywordDao.getByScopeFlow(scope)

    /** 某作用域已启用规则（按 sort_order、id 升序），供扫描/解析时应用。 */
    suspend fun getEnabledRules(scope: String): List<KeywordReplaceRuleEntity> =
        keywordDao.getEnabledByScope(scope)

    /** 某作用域当前最大排序号，新规则默认追加到末尾。 */
    suspend fun maxRuleSortOrder(scope: String): Int = keywordDao.maxSortOrder(scope)

    suspend fun upsertRule(rule: KeywordReplaceRuleEntity) = keywordDao.upsert(rule)
    suspend fun deleteRule(rule: KeywordReplaceRuleEntity) = keywordDao.deleteById(rule.id)
    suspend fun setRuleEnabled(id: Long, enabled: Boolean) = keywordDao.setEnabled(id, enabled)

    /**
     * 按“书名 + 作者”相同标记重复（文件名解析结果），每组保留首个，其余标记。
     * 返回本次标记的条数。
     */
    suspend fun markDuplicatesByName(runId: Long): Int {
        val n = dao.markDuplicatesByNameSql(runId)
        LogUtil.i("Repo", "markDuplicatesByName marked $n files (run=$runId)")
        return n
    }

    /**
     * 分页加载文库列表。
     * [filter]："ALL" / "MARKED" / "DUPLICATES"
     * [hashes]：当 filter=DUPLICATES 时传入重复内容哈希集合（由调用方先取一次，避免每页重复计算）
     * [query]：搜索关键字（文件名/书名/作者，含转义）
     * [sort]："TIME" / "NAME" / "SIZE"
     */
    fun pagedFiles(
        filter: String,
        query: String,
        sort: String,
        runId: Long,
        pageSize: Int = 100
    ): Flow<PagingData<ScannedFileEntity>> {
        val where = mutableListOf<String>()
        where += "scan_run_id = $runId"
        if (filter == "MARKED") where += "marked = 1"
        val q = query.trim()
        if (q.isNotEmpty()) {
            val safe = q.replace("'", "''")
            where += "(file_name LIKE '%$safe%' OR title LIKE '%$safe%' OR author LIKE '%$safe%')"
        }
        val orderBy = when (sort) {
            "NAME" -> "file_name ASC"
            "SIZE" -> "file_size DESC"
            else -> "created_at DESC"
        }
        val sql = buildString {
            append("SELECT * FROM scanned_file")
            if (where.isNotEmpty()) append(" WHERE ${where.joinToString(" AND ")}")
            append(" ORDER BY $orderBy")
        }
        return Pager(
            config = PagingConfig(pageSize = pageSize, enablePlaceholders = false, initialLoadSize = pageSize * 2)
        ) {
            dao.pagedRaw(SimpleSQLiteQuery(sql))
        }.flow
    }

    // ===================== 真·页码分页（LIMIT/OFFSET + Flow 自动刷新） =====================

    /** 拼装列表模式的 WHERE 子句（筛选 + 搜索），列表页与计数共用，保证两者口径一致。 */
    private fun buildFilesWhere(filter: String, query: String, runId: Long): String {
        val where = mutableListOf<String>()
        where += "scan_run_id = $runId"
        if (filter == "MARKED") where += "marked = 1"
        val q = query.trim()
        if (q.isNotEmpty()) {
            val safe = q.replace("'", "''")
            where += "(file_name LIKE '%$safe%' OR title LIKE '%$safe%' OR author LIKE '%$safe%')"
        }
        return where.joinToString(" AND ")
    }

    /**
     * 列表模式：取第 [page] 页（0 基）的文件，每页 [pageSize] 条。用 LIMIT/OFFSET 只查一页，
     * 返回 Flow：标记/删除等写操作后 Room 自动重发当前页，无需手动刷新。
     */
    fun filesPageFlow(
        filter: String,
        query: String,
        sort: String,
        runId: Long,
        pageSize: Int,
        page: Int
    ): Flow<List<ScannedFileEntity>> {
        val where = buildFilesWhere(filter, query, runId)
        val orderBy = when (sort) {
            "NAME" -> "file_name ASC"
            "SIZE" -> "file_size DESC"
            else -> "created_at DESC"
        }
        val limit = pageSize.coerceAtLeast(1)
        val offset = (page.coerceAtLeast(0)) * limit
        val sql = "SELECT * FROM scanned_file WHERE $where ORDER BY $orderBy LIMIT $limit OFFSET $offset"
        return dao.filesPageFlow(SimpleSQLiteQuery(sql))
    }

    /** 列表模式：符合筛选/搜索条件的总条数（Flow），用于计算总页数并随表变化自动更新。 */
    fun filesCountFlow(filter: String, query: String, runId: Long): Flow<Int> {
        val where = buildFilesWhere(filter, query, runId)
        val sql = "SELECT COUNT(*) FROM scanned_file WHERE $where"
        return dao.filesCountFlow(SimpleSQLiteQuery(sql))
    }

    /** 拼装合集模式的 WHERE / HAVING（分组页与分组计数共用）。返回 (whereSql, havingSql)。 */
    private fun buildGroupsClauses(
        minCount: Int,
        maxCount: Int,
        excludeNames: List<String>,
        query: String,
        runId: Long
    ): Pair<String, String> {
        val where = mutableListOf<String>()
        where += "scan_run_id = $runId"
        val q = query.trim()
        if (q.isNotEmpty()) {
            val safe = q.replace("'", "''")
            where += "(file_name LIKE '%$safe%' OR title LIKE '%$safe%' OR author LIKE '%$safe%')"
        }
        val having = mutableListOf<String>()
        if (minCount > 0) having += "COUNT(*) >= $minCount"
        if (maxCount >= 0) having += "COUNT(*) <= $maxCount"
        if (excludeNames.isNotEmpty()) {
            val inList = excludeNames.joinToString(",") { "'${it.replace("'", "''")}'" }
            having += "title NOT IN ($inList)"
        }
        val whereSql = where.joinToString(" AND ")
        val havingSql = if (having.isNotEmpty()) " HAVING ${having.joinToString(" AND ")}" else ""
        return whereSql to havingSql
    }

    /** 合集模式：取第 [page] 页（0 基）的分组，每页 [pageSize] 个。 */
    fun groupsPageFlow(
        minCount: Int,
        maxCount: Int,
        excludeNames: List<String>,
        query: String,
        runId: Long,
        pageSize: Int,
        page: Int
    ): Flow<List<NovelGroup>> {
        val (whereSql, havingSql) = buildGroupsClauses(minCount, maxCount, excludeNames, query, runId)
        val limit = pageSize.coerceAtLeast(1)
        val offset = (page.coerceAtLeast(0)) * limit
        val sql = buildString {
            append("SELECT title AS group_title, COUNT(*) AS file_count, SUM(file_size) AS total_size")
            append(" FROM scanned_file WHERE $whereSql GROUP BY title")
            append(havingSql)
            append(" ORDER BY (title = '') ASC, file_count DESC, title ASC")
            append(" LIMIT $limit OFFSET $offset")
        }
        return dao.groupsPageFlow(SimpleSQLiteQuery(sql))
    }

    /** 合集模式：符合区间/排除/搜索条件的分组总数（Flow）。 */
    fun groupsCountFlow(
        minCount: Int,
        maxCount: Int,
        excludeNames: List<String>,
        query: String,
        runId: Long
    ): Flow<Int> {
        val (whereSql, havingSql) = buildGroupsClauses(minCount, maxCount, excludeNames, query, runId)
        // 分组数 = 外层 COUNT 包裹「GROUP BY + HAVING」的结果集
        val sql = "SELECT COUNT(*) FROM (SELECT title FROM scanned_file WHERE $whereSql GROUP BY title$havingSql)"
        return dao.groupsCountFlow(SimpleSQLiteQuery(sql))
    }

    /**
     * 合集模式：按书名分组的分页列表。
     * [minCount]/[maxCount]：合集文件数区间（maxCount<0 表示不限）。
     * [excludeNames]：排除的书名列表。
     * [query]：搜索关键字（匹配书名/作者/文件名）。
     * 空书名合集显示为“未解析”，排序时置底。
     */
    fun pagedGroups(
        minCount: Int,
        maxCount: Int,
        excludeNames: List<String>,
        query: String,
        runId: Long,
        pageSize: Int = 100
    ): Flow<PagingData<NovelGroup>> {
        val where = mutableListOf<String>()
        where += "scan_run_id = $runId"
        val q = query.trim()
        if (q.isNotEmpty()) {
            val safe = q.replace("'", "''")
            where += "(file_name LIKE '%$safe%' OR title LIKE '%$safe%' OR author LIKE '%$safe%')"
        }
        val having = mutableListOf<String>()
        if (minCount > 0) having += "COUNT(*) >= $minCount"
        if (maxCount >= 0) having += "COUNT(*) <= $maxCount"
        if (excludeNames.isNotEmpty()) {
            val inList = excludeNames.joinToString(",") { "'${it.replace("'", "''")}'" }
            having += "title NOT IN ($inList)"
        }
        val sql = buildString {
            append("SELECT title AS group_title, COUNT(*) AS file_count, SUM(file_size) AS total_size")
            append(" FROM scanned_file")
            if (where.isNotEmpty()) append(" WHERE ${where.joinToString(" AND ")}")
            append(" GROUP BY title")
            if (having.isNotEmpty()) append(" HAVING ${having.joinToString(" AND ")}")
            append(" ORDER BY (title = '') ASC, file_count DESC, title ASC")
        }
        return Pager(
            config = PagingConfig(pageSize = pageSize, enablePlaceholders = false, initialLoadSize = pageSize * 2)
        ) {
            dao.pagedGroupsRaw(SimpleSQLiteQuery(sql))
        }.flow
    }

    /** 取某合集内全部文件（展开时懒加载）。 */
    suspend fun getFilesByTitle(runId: Long, title: String): List<ScannedFileEntity> =
        dao.getFilesByTitle(runId, title)

    /** 取某文库下参与重复判定的全部行（作者非空），供 ViewModel 分块计算合集重复进度。 */
    suspend fun getDuplicateRows(runId: Long): List<DuplicateRow> = dao.getDuplicateRows(runId)

    /**
     * 复刻 PC 端 /api/groups/select-duplicates 的“标记重复”逻辑，只计算应勾选（待删）的 id：
     * 按 (书名 + 作者) 分组；作者为空跳过；仅当组内纯数字进度条目 >= 2 才处理：
     *   - 组内任一行进度含“完结/番外/完本/全本” → 所有纯数字进度行勾选
     *   - 否则 → 保留进度值最大的一行，其余纯数字行勾选
     * 若组内 file_size 最大的行被勾选，则取消（保留最大文件）。
     * 返回应勾选的 id 列表（不直接写库，交 ViewModel 并入 selection）。
     */
    suspend fun selectDuplicateIds(runId: Long): List<Long> {
        val rows = dao.getDuplicateRows(runId)
        val groupedAll = LinkedHashMap<Pair<String, String>, MutableList<Triple<Long, String, Long>>>()
        val groupedNumeric = LinkedHashMap<Pair<String, String>, MutableList<Triple<Long, Int, Long>>>()
        for (r in rows) {
            val author = r.author.trim()
            if (author.isEmpty()) continue
            val key = r.title.trim() to author
            val progress = r.progress.trim()
            groupedAll.getOrPut(key) { mutableListOf() }.add(Triple(r.id, progress, r.fileSize))
            if (progress.isNotEmpty() && progress.all { it.isDigit() }) {
                groupedNumeric.getOrPut(key) { mutableListOf() }.add(Triple(r.id, progress.toInt(), r.fileSize))
            }
        }
        val completionKeywords = listOf("完结", "番外", "完本", "全本")
        val result = mutableListOf<Long>()
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
        LogUtil.i("Repo", "selectDuplicateIds for run=$runId -> ${result.size} ids")
        return result
    }


    /**
     * 导出已标记文件清单到应用私有外部目录，返回文件路径（失败返回 null）。
     */
    suspend fun exportMarked(context: android.content.Context): String? {
        return try {
            val marked = dao.getMarked()
            ExportService.writeMarked(context, marked)
        } catch (e: Exception) {
            LogUtil.e("Repo", "exportMarked failed: ${e.message}")
            null
        }
    }

    /**
     * 删除确认页使用：把待删 id 列表分页加载成实体，前端可滚动浏览全部待删文件，
     * 而非仅预览前若干条。仍按 Paging3 思路分批（每页 60 条），由内存 id 列表驱动分页，
     * 每页用 IN 子句回 Room 取实体，避免一次性把 10w 行读进内存。
     */
    fun pagedByIds(ids: List<Long>): Flow<PagingData<ScannedFileEntity>> {
        if (ids.isEmpty()) return flowOf(PagingData.empty())
        return Pager(
            config = PagingConfig(pageSize = 60, enablePlaceholders = false, initialLoadSize = 120)
        ) {
            IdsPagingSource(ids, this)
        }.flow
    }

    /**
     * 基于内存 id 列表的分页源：按页切出 id 子集，回 Room 取对应实体。
     * 分页键用页号（Int），刷新键按锚点位置回推。
     */
    private class IdsPagingSource(
        private val ids: List<Long>,
        private val repo: FileRepository
    ) : PagingSource<Int, ScannedFileEntity>() {
        override suspend fun load(params: LoadParams<Int>): LoadResult<Int, ScannedFileEntity> {
            val page = params.key ?: 0
            val start = page * params.loadSize
            if (start >= ids.size) {
                return LoadResult.Page(emptyList(), prevKey = null, nextKey = null)
            }
            val end = if (start + params.loadSize < ids.size) start + params.loadSize else ids.size
            val items = repo.getByIds(ids.subList(start, end))
            val prevKey = if (page == 0) null else page - 1
            val nextKey = if (end >= ids.size) null else page + 1
            return LoadResult.Page(items, prevKey = prevKey, nextKey = nextKey)
        }

        override fun getRefreshKey(state: PagingState<Int, ScannedFileEntity>): Int? {
            return state.anchorPosition?.let { anchor ->
                state.closestPageToPosition(anchor)?.let { page ->
                    page.prevKey?.plus(1) ?: page.nextKey?.minus(1)
                }
            }
        }
    }
}
