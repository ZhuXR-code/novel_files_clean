package com.filescanner.app.data.repository

import com.filescanner.app.data.database.dao.ScannedFileDao
import com.filescanner.app.data.database.dao.ScanRunDao
import com.filescanner.app.data.database.dao.KeywordReplaceDao
import com.filescanner.app.data.database.entity.ScannedFileEntity
import com.filescanner.app.data.database.entity.ScanRunEntity
import com.filescanner.app.data.database.entity.KeywordReplaceRuleEntity
import com.filescanner.app.util.KeywordReplace
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

    /**
     * 删除文件后，按 [runId] 重算文库文件数并回写 scan_run.file_count，
     * 使文库列表展示的文件数与实际剩余记录数一致（修复“文件已删、文库列表数不变”）。
     */
    suspend fun recomputeRunFileCount(runId: Long) {
        val n = dao.countByRunSync(runId)
        runDao.setFileCount(runId, n)
        LogUtil.i("Repo", "recomputeRunFileCount run=$runId -> $n")
    }

    /**
     * 删除文库：删除文库（scan_run）记录，并一并删除其下属书籍的数据库记录（scanned_file），
     * 即“文库 + 书籍记录”整体从库中清除。注意这里只删数据库记录，
     * 不删除手机上的真实源文件（txt 等物理文件由用户另行管理），避免误删用户文件。
     */
    suspend fun deleteScanRun(runId: Long) {
        dao.deleteByRunId(runId)
        runDao.deleteById(runId)
    }

    suspend fun getById(id: Long): ScannedFileEntity? = dao.getById(id)
    suspend fun getByIds(ids: List<Long>): List<ScannedFileEntity> = dao.getByIds(ids)
    suspend fun getMarked(): List<ScannedFileEntity> = dao.getMarked()

    /** 勾选（checked）相关：与 marked(星标) 完全独立。 */
    suspend fun setChecked(id: Long, checked: Boolean) = dao.setChecked(id, if (checked) 1 else 0)
    suspend fun setCheckedForIds(ids: List<Long>, checked: Boolean) {
        if (ids.isNotEmpty()) dao.setCheckedForIds(ids, if (checked) 1 else 0)
    }
    suspend fun clearChecked(runId: Long) = dao.clearChecked(runId)
    suspend fun getCheckedIds(runId: Long): List<Long> = dao.getCheckedIds(runId)
    fun checkedCountFlow(runId: Long): Flow<Int> = dao.checkedCountFlow(runId)
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
     * 补齐缺失的预置关键词替换规则（幂等）：按 pattern 判断，仅插入库中尚不存在的默认项。
     * 首次为空时整批写入；后续新增预置项也会自动补进已安装实例，无需清数据。
     * 只动数据库记录，不触碰手机上的源文件。返回本次新增的条数。
     */
    suspend fun seedDefaultKeywordRules(): Int {
        var added = 0
        for (rule in KeywordReplace.DEFAULT_KEYWORD_RULES) {
            if (keywordDao.countByScopeAndPattern(rule.scope, rule.pattern) == 0) {
                keywordDao.upsert(rule)
                added++
            }
        }
        return added
    }

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
        if (filter == "UNMARKED") where += "marked = 0"
        if (filter == "CHECKED") where += "checked = 1"
        if (filter == "UNCHECKED") where += "checked = 0"
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
        if (filter == "UNMARKED") where += "marked = 0"
        if (filter == "CHECKED") where += "checked = 1"
        if (filter == "UNCHECKED") where += "checked = 0"
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
        runId: Long,
        filter: String = "ALL"
    ): Pair<String, String> {
        val where = mutableListOf<String>()
        where += "scan_run_id = $runId"
        if (filter == "MARKED") where += "marked = 1"
        if (filter == "UNMARKED") where += "marked = 0"
        if (filter == "CHECKED") where += "id IN (SELECT id FROM scanned_file WHERE scan_run_id = $runId AND checked = 1)"
        if (filter == "UNCHECKED") where += "id NOT IN (SELECT id FROM scanned_file WHERE scan_run_id = $runId AND checked = 1)"
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
        page: Int,
        filter: String = "ALL"
    ): Flow<List<NovelGroup>> {
        val (whereSql, havingSql) = buildGroupsClauses(minCount, maxCount, excludeNames, query, runId, filter)
        val limit = pageSize.coerceAtLeast(1)
        val offset = (page.coerceAtLeast(0)) * limit
        val sql = buildString {
            append("SELECT title AS group_title, COUNT(*) AS file_count, SUM(file_size) AS total_size, SUM(checked) AS checked_count")
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
        runId: Long,
        filter: String = "ALL"
    ): Flow<Int> {
        val (whereSql, havingSql) = buildGroupsClauses(minCount, maxCount, excludeNames, query, runId, filter)
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
            append("SELECT title AS group_title, COUNT(*) AS file_count, SUM(file_size) AS total_size, SUM(checked) AS checked_count")
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

    /** 取某合集内全部文件（展开时懒加载）。[marked]/[checked] 为 null 不过滤，1/0 按对应字段筛选。 */
    suspend fun getFilesByTitle(runId: Long, title: String, marked: Int? = null, checked: Int? = null): List<ScannedFileEntity> =
        dao.getFilesByTitle(runId, title, marked, checked)

    /** 取某文库下参与重复判定的全部行（作者非空），供 ViewModel 分块计算合集重复进度。 */
    suspend fun getDuplicateRows(runId: Long): List<DuplicateRow> = dao.getDuplicateRows(runId)

    /**
     * 复刻并增强 PC 端 /api/groups/select-duplicates 的“标记重复”逻辑，只计算应勾选（待删）的 id。
     * 所有判定在【同一文库】内、按 (作者 + 书名) 子分组进行五则规则（与 backend/dup_logic.py 完全一致）：
     *
     * 规则 1（完全相等去重）：(文件名 + 大小 + 书名 + 作者 + 进度) 五字段完全一致，
     *     且同组 >= 2 本时，最新(createdAt 最晚，并列取 id 最大)的不勾选，其余全部勾选。
     * 规则 2（纯数字进度对比）：同 (作者+书名) 内，若【所有】进度均为纯数字，则
     *     进度数字最大的不勾选，其余纯数字文件全部勾选。
     * 规则 3（含中文进度 / 完结特例）：
     *     - 进度含中文(如“完结/连载/断更”)的，不勾选（保护状态文件）；
     *     - 若同组存在文件名带『完结』等关键词、且“进度数字最大文件”的大小
     *       小于同组所有含中文进度文件的大小时，该“进度数字最大文件”也要勾选
     *       （说明存在更完整的完结版，部分进度版冗余应删）。
     * 规则 4（最大文件不勾选原则）：已勾选的文件若为本 (作者+书名) 组内文件大小最大者，则不勾选。
     *
     * 返回应勾选的 id 列表，并直接把结果【持久化写入 checked=1】——标记重复即“勾选”，
     * 与 marked(星标) 完全无关。仅新增勾选、不清空其它已勾选，保证“合并勾选”语义。
     */
    suspend fun selectDuplicateIds(runId: Long): List<Long> {
        val rows = dao.getDuplicateRows(runId)
        // 按 (作者 + 书名) 子分组
        val subgroups = rows.groupBy { subKey(it.author, it.title) }
        val allResult = mutableSetOf<Long>()
        var subgroupsWithDups = 0
        val detailLines = mutableListOf<String>()

        for ((_, S) in subgroups) {
            if (S.size < 2) continue

            val c = mutableSetOf<Long>()   // 应勾选
            val nc = mutableSetOf<Long>()  // 永不勾选（保护）
            val fc = mutableSetOf<Long>()  // 强制勾选（覆盖保护）

            // 规则 1：五字段完全相等的精确重复组
            val exact = S.groupBy { Triple(it.fileName, it.fileSize, it.progress.trim()) }
            for ((_, g) in exact) {
                if (g.size < 2) continue
                val newest = g.maxWithOrNull(compareBy<DuplicateRow> { it.createdAt }.thenBy { it.id })!!
                nc.add(newest.id)
                for (f in g) if (f.id != newest.id) {
                    // 精确重复的非最新本：强制勾选（覆盖规则2“最大进度不勾选”的保护；
                    // 精确重复=同尺寸，不可能同时是“唯一最大文件”，故不会与规则4冲突）。
                    c.add(f.id)
                    fc.add(f.id)
                }
            }

            // 进度分类
            val numericFiles = S.filter { progressValue(it.progress) != null }
            val chineseFiles = S.filter { hasCjk(it.progress) }
            val allNumeric = numericFiles.size == S.size

            if (allNumeric) {
                // 规则 2：纯数字进度，最大者不勾选，其余纯数字全部勾选
                val maxVal = S.maxOf { progressValue(it.progress)!! }
                val maxFiles = S.filter { progressValue(it.progress) == maxVal }
                val maxIds = maxFiles.map { it.id }.toSet()
                maxFiles.forEach { nc.add(it.id) }
                S.forEach { if (it.id !in maxIds) c.add(it.id) }
            } else {
                // 规则 3A：含中文进度者不勾选
                chineseFiles.forEach { nc.add(it.id) }
                // 规则 3B：完结特例——进度数字最大文件更小则强制勾选
                if (chineseFiles.isNotEmpty() && numericFiles.isNotEmpty()) {
                    val maxNumVal = numericFiles.maxOf { progressValue(it.progress)!! }
                    val maxNumFiles = numericFiles.filter { progressValue(it.progress) == maxNumVal }
                    val hasCompletion = S.any { cf -> COMPLETION_KW.any { kw -> (cf.fileName).contains(kw) } }
                    val minChineseSize = chineseFiles.minOf { it.fileSize }
                    if (hasCompletion && maxNumFiles.all { mn -> mn.fileSize < minChineseSize }) {
                        maxNumFiles.forEach { fc.add(it.id) }
                    }
                }
            }

            // 规则 4：本组内【唯一】文件大小最大者，不勾选（最大文件不勾选原则）。
            //   若多本并列最大则按大小无法区分，不据此保护，以免同大小重复组被整体保留。
            val maxSize = S.maxOf { it.fileSize }
            val maxSizeCount = S.count { it.fileSize == maxSize }
            if (maxSizeCount == 1) {
                S.forEach { if (it.fileSize == maxSize) nc.add(it.id) }
            }

            // 规则 5（新增）：完结+N番外 组合排序去重。
            //   进度【严格】匹配 `完结+数字番外`（如「完结+3番外」）的文件，在同 (作者+书名)
            //   组内按数字 N 排序；数字最大者不勾选，其余打勾（强制勾选，覆盖规则③A 对中文进度的保护）；
            //   但被勾选的文件若恰为本组 (作者+书名) 内【文件大小最大者】，则也不勾选。
            val fanwai = S.filter { fanwaiValue(it.progress) != null }
            if (fanwai.isNotEmpty()) {
                val maxN = fanwai.maxOf { fanwaiValue(it.progress)!! }
                val maxNIds = fanwai.filter { fanwaiValue(it.progress) == maxN }.map { it.id }.toSet()
                for (f in fanwai) {
                    when {
                        f.id in maxNIds -> { nc.add(f.id); fc.remove(f.id) }   // 数字最大：不勾选
                        f.fileSize == maxSize -> { nc.add(f.id); fc.remove(f.id) } // 本组文件大小最大：不勾选
                        else -> { c.add(f.id); fc.add(f.id) }                   // 强制勾选，覆盖规则③A
                    }
                }
            }

            val subResult = (c - nc) + fc
            if (subResult.isNotEmpty()) {
                subgroupsWithDups++
                val nv = S[0].title.ifEmpty { "?" }
                val au = S[0].author.ifEmpty { "?" }
                detailLines.add(
                    "标记重复-重复子组 书名=$nv 作者=$au 共${S.size}本 -> 勾选${subResult.size}个: ${subResult.sorted()}"
                )
                allResult += subResult
            }
        }
        LogUtil.i(
            "Repo",
            "标记重复 完成 run=$runId 重复子组=$subgroupsWithDups 应勾选=${allResult.size} 个"
        )
        if (detailLines.isNotEmpty()) LogUtil.i("Repo", detailLines.joinToString("\n"))
        if (allResult.isNotEmpty()) setCheckedForIds(allResult.toList(), true)
        return allResult.toList()
    }

    /** 文件名中代表“已完结/完整版”的关键词：用于规则 3 的特例判定。 */
    private val COMPLETION_KW = listOf("完结", "完本", "全本", "全集", "完整", "全套", "全集版")

    /** 进度【严格】匹配「完结+数字番外」正则（用于规则 5 的完结+N番外 组合排序）。 */
    private val FANWAI_RE = Regex("""^完结\+(\d+(?:\.\d+)?)番外$""")

    /** 判断字符串是否含有中文（CJK）字符。 */
    private fun hasCjk(s: String?): Boolean {
        if (s.isNullOrEmpty()) return false
        for (c in s) {
            val o = c.code
            if (o in 0x4E00..0x9FFF || o in 0x3400..0x4DBF) return true
        }
        return false
    }

    /** 若进度为纯数字（可选小数、可选尾随 %），返回 Double 数值，否则返回 null。 */
    private fun progressValue(s: String?): Double? {
        val t = (s ?: "").trim()
        if (t.isEmpty() || hasCjk(t)) return null
        val m = Regex("""^(\d+(?:\.\d+)?)\s*%?$""").matchEntire(t) ?: return null
        return m.groupValues[1].toDoubleOrNull()
    }

    /** 若进度严格匹配「完结+数字番外」（如「完结+3番外」），返回数字 N，否则 null。 */
    private fun fanwaiValue(s: String?): Double? {
        val t = (s ?: "").trim()
        if (t.isEmpty()) return null
        val m = FANWAI_RE.matchEntire(t) ?: return null
        return m.groupValues[1].toDoubleOrNull()
    }

    /** (作者 + 书名) 归一化子分组键（统一小写、去空格）。 */
    private fun subKey(author: String, title: String): String =
        "${author.trim().lowercase()}\u0000${title.trim().lowercase()}"


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
