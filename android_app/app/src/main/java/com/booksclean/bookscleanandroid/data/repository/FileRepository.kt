package com.bookscleanandroid.app.data.repository

import com.bookscleanandroid.app.data.database.dao.DupRuleConfigDao
import com.bookscleanandroid.app.data.database.dao.FileNoteDao
import com.bookscleanandroid.app.data.database.dao.ScannedFileDao
import com.bookscleanandroid.app.data.database.dao.ScanRunDao
import com.bookscleanandroid.app.data.database.dao.KeywordReplaceDao
import com.bookscleanandroid.app.data.database.entity.DupRuleConfigEntity
import com.bookscleanandroid.app.data.database.entity.FileNoteEntity
import com.bookscleanandroid.app.data.database.entity.ScannedFileEntity
import com.bookscleanandroid.app.data.database.entity.ScanRunEntity
import com.bookscleanandroid.app.data.database.entity.KeywordReplaceRuleEntity
import com.bookscleanandroid.app.util.KeywordReplace
import com.bookscleanandroid.app.data.database.entity.DuplicateRow
import com.bookscleanandroid.app.data.model.NovelGroup
import com.bookscleanandroid.app.util.ExportService
import com.bookscleanandroid.app.util.LogUtil
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
    private val keywordDao: KeywordReplaceDao,
    private val dupRuleDao: DupRuleConfigDao? = null,
    private val fileNoteDao: FileNoteDao
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
     * 使文库列表展示的文件数与实际剩余记录数一致（修复"文件已删、文库列表数不变"）。
     */
    suspend fun recomputeRunFileCount(runId: Long) {
        val n = dao.countByRunSync(runId)
        runDao.setFileCount(runId, n)
        LogUtil.i("Repo", "recomputeRunFileCount run=$runId -> $n")
    }

    /**
     * 删除文库：删除文库（scan_run）记录，并一并删除其下属书籍的数据库记录（scanned_file），
     * 即"文库 + 书籍记录"整体从库中清除。注意这里只删数据库记录，
     * 不删除手机上的真实源文件（txt 等物理文件由用户另行管理），避免误删用户文件。
     */
    suspend fun deleteScanRun(runId: Long) {
        dao.deleteByRunId(runId)
        runDao.deleteById(runId)
    }

    /**
     * 合并多个文库为一个新文库。
     * sourceIds 为待合并的文库 id（≥2），newName 为用户指定的新文库名称。
     * 合并后：所有源文库的文件（保留勾选/标记/书名/作者等全部状态）归入新文库，
     * 相同 path 跨文库自动去重（每个 path 保留一条）；源文库被删除。
     * 返回新建文库的 id。
     */
    suspend fun mergeRuns(sourceIds: List<Long>, newName: String): Long {
        require(sourceIds.size >= 2) { "合并文库至少需要选择 2 个" }
        val newId = runDao.mergeRuns(sourceIds, newName, System.currentTimeMillis())
        // 合并备注：按 path 把源文库文件备注复制到新文库文件下。
        // 同一 path 在合并后只保留一条（新 file_id），多个源文库对同一 path 的备注
        // 经 file_notes 唯一索引 (file_id, content) 自动去重（区分大小写）。
        // 使用单语句 JOIN（copyNotesOnMerge）在 DB 内部完成 path 重映射，
        // 避免 20w 级别书库下「全量读取 path + 巨型 IN + 内存 map」导致的内存与参数上限问题。
        fileNoteDao.copyNotesOnMerge(newId, sourceIds)
        LogUtil.i("Repo", "mergeRuns 已复制源文库备注 -> 新文库 newId=$newId")
        return newId
    }

    // ===================== 文件备注（file_notes）管理 =====================
    /** 取某文件全部备注（实时流，供详情页展示）。 */
    fun getFileNotesFlow(fileId: Long) = fileNoteDao.getNotesByFile(fileId)

    /**
     * 新增备注。content 须 1~50 字；同一文件内内容（区分大小写）重复则抛
     * IllegalStateException，由调用方提示用户。
     */
    suspend fun addFileNote(fileId: Long, content: String): FileNoteEntity {
        val c = content.trim()
        require(c.isNotEmpty() && c.length <= 50) { "备注内容须为 1~50 字" }
        val entity = FileNoteEntity(fileId = fileId, content = c)
        try {
            fileNoteDao.insert(entity)
        } catch (e: android.database.sqlite.SQLiteConstraintException) {
            throw IllegalStateException("该文件已存在相同内容的备注", e)
        }
        // 重新取出（带自增 id / createdAt）
        return fileNoteDao.getNotesByFileOnce(fileId).firstOrNull { it.content == c }
            ?: entity
    }

    /** 编辑备注内容，规则同新增。 */
    suspend fun updateFileNote(noteId: Long, fileId: Long, content: String) {
        val c = content.trim()
        require(c.isNotEmpty() && c.length <= 50) { "备注内容须为 1~50 字" }
        val existing = fileNoteDao.getNotesByFileOnce(fileId).firstOrNull { it.id == noteId }
            ?: throw IllegalStateException("备注不存在")
        try {
            fileNoteDao.update(existing.copy(content = c))
        } catch (e: android.database.sqlite.SQLiteConstraintException) {
            throw IllegalStateException("该文件已存在相同内容的备注", e)
        }
    }

    suspend fun deleteFileNote(noteId: Long) = fileNoteDao.deleteById(noteId)

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

    /**
     * 跨文库同步删除：在 APP 内删除文件（含源文件）时，同一物理文件可能出现在多个文库中，
     * 需要把所有文库里记录该 path 的行一并删除。步骤：
     *   1) 取待删 id 对应的 path 集合；
     *   2) 对每个 path，删掉所有文库中该 path 的行，并收集其中命中的 scan_run_id；
     *   3) 重算所有受影响文库的 file_count。
     */
    suspend fun deleteFilesSynced(ids: List<Long>) {
        if (ids.isEmpty()) return
        LogUtil.i("Repo", "deleteFilesSynced 开始同步删除 ${ids.size} 条")
        val paths = dao.getPathsByIds(ids)
        val affectedRuns = mutableSetOf<Long>()
        for (p in paths) {
            val runs = dao.getRunsByPath(p)
            affectedRuns.addAll(runs)
            dao.deleteByPath(p)
        }
        for (rid in affectedRuns) {
            val c = dao.countByRunSync(rid)
            dao.setRunFileCount(rid, c)
        }
        LogUtil.i("Repo", "deleteFilesSynced 完成，涉及文库 ${affectedRuns.size} 个")
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

    /** 批量启用 / 停用规则（分批 900 条，规避 SQLite 变量数上限）。 */
    suspend fun setRulesEnabled(ids: List<Long>, enabled: Boolean) {
        if (ids.isEmpty()) return
        ids.chunked(900).forEach { keywordDao.setEnabledBatch(it, enabled) }
    }

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

    // ===================== 勾选重复规则配置 =====================
    /** 取已启用规则的 ruleKey 集合（默认全部启用）。 */
    suspend fun getEnabledDupRuleKeys(): Set<String> {
        return if (dupRuleDao != null) {
            dupRuleDao.getEnabledBuiltinRuleKeys().toSet()
        } else {
            // 兼容无 DAO 场景：全部启用
            setOf("rule1", "rule2", "rule3a", "rule3b", "rule4", "rule5", "rule_hash")
        }
    }

    /** 幂等补齐缺失的默认勾选重复规则配置。 */
    suspend fun seedDefaultDupRules() {
        if (dupRuleDao == null) return
        // 先清理历史上因缺少 UNIQUE 约束、每次启动都重新插入而重复的内置规则（每个 rule_key 只保留一条）
        try { dupRuleDao.dedupByKey() } catch (_: Exception) {}
        val defaults = listOf(
            DupRuleConfigEntity(ruleKey = "rule1", ruleName = "精确重复去重", enabled = true, description = "小说名+作者+进度+文件大小完全相等的文件，保留最新一个", isBuiltin = true, sortOrder = 0),
            DupRuleConfigEntity(ruleKey = "rule2", ruleName = "纯数字进度对比", enabled = true, description = "有纯数字进度的文件中，进度最高的不勾选，其余勾选", isBuiltin = true, sortOrder = 0),
            DupRuleConfigEntity(ruleKey = "rule3a", ruleName = "含中文进度保护", enabled = true, description = "含有中文进度（如\"更新至50\"）的文件不勾选", isBuiltin = true, sortOrder = 0),
            DupRuleConfigEntity(ruleKey = "rule3b", ruleName = "完结特例", enabled = true, description = "同一本书若同时有『完结版』(文件名含『完结/全本』)与纯数字进度的文件：当数字进度最大的文件体积小于所有『完结字样』文件中最小的那个，说明它不完整，会勾选删除，只留下完结版。", isBuiltin = true, sortOrder = 0),
            DupRuleConfigEntity(ruleKey = "rule4", ruleName = "最大文件不勾选", enabled = true, description = "同一组内文件大小唯一最大的文件不勾选", isBuiltin = true, sortOrder = 0),
            DupRuleConfigEntity(ruleKey = "rule5", ruleName = "完结+N番外/番外N去重", enabled = true, description = "进度匹配\"完结+N番外\"或\"完结+番外N\"的组内，按番外数 N 排序，最大 N 不勾选，其余勾选", isBuiltin = true, sortOrder = 0),
            DupRuleConfigEntity(ruleKey = "rule_hash", ruleName = "内容哈希去重", enabled = true, description = "对「已扫描内容哈希」的文件，按内容哈希全局（跨合集）分组：同一哈希值内保留最新一个（不勾选），其余哈希相同但非最新的文件勾选删除。无哈希的文件不受此规则影响，仍按其它规则处理。", isBuiltin = true, sortOrder = 0),
        )
        for (rule in defaults) {
            // 按 key 计数判断，库中不存在才插入；不依赖 UNIQUE 冲突忽略，
            // 避免全新安装（rule_key 无 UNIQUE 约束）时每次启动重复插入。
            if (dupRuleDao.countByKey(rule.ruleKey) == 0) {
                dupRuleDao.insertIfNotExists(rule)
            } else {
                // 记录已存在：同步内置规则的最新说明文案，
                // 让存量库的「勾选重复规则」页面也能看到优化后的描述（不改动用户开关）。
                dupRuleDao.refreshBuiltinDescription(rule.ruleKey, rule.description)
            }
        }
    }

    /**
     * 按"书名 + 作者"相同勾选重复（文件名解析结果），每组保留首个，其余标记。
     * 返回本次标记的条数。
     */
    suspend fun markDuplicatesByName(runId: Long): Int {
        val n = dao.markDuplicatesByNameSql(runId)
        LogUtil.i("Repo", "markDuplicatesByName marked $n files (run=$runId)")
        return n
    }

    /**
     * 按“内容哈希相同、修改时间更早”标记重复文件。
     * 同一 hash 组内仅保留最新修改（file_date 优先，回退 created_at，相同取最大 id）的那条不标记，
     * 其余更早的标记 marked=1。返回本次标记的条数；若该文库未扫描内容哈希则返回 -1（提示用户）。
     */
    suspend fun markDuplicatesByHash(runId: Long): Int {
        if (dao.hasContentHash(runId) == 0) return -1
        val n = dao.markDuplicatesByHashSql(runId)
        LogUtil.i("Repo", "markDuplicatesByHash marked $n files (run=$runId)")
        return n
    }

    /**
     * 按“内容哈希相同、修改时间更早”勾选重复文件。逻辑同 markDuplicatesByHash，仅置 checked=1。
     */
    suspend fun checkDuplicatesByHash(runId: Long): Int {
        if (dao.hasContentHash(runId) == 0) return -1
        val n = dao.checkDuplicatesByHashSql(runId)
        LogUtil.i("Repo", "checkDuplicatesByHash checked $n files (run=$runId)")
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
            where += "(file_name LIKE '%$safe%' OR title LIKE '%$safe%' OR author LIKE '%$safe%' OR title_pinyin LIKE '%$safe%' OR author_pinyin LIKE '%$safe%' OR id IN (SELECT file_id FROM file_notes WHERE content LIKE '%$safe%'))"
        }
        val orderBy = when (sort) {
            "NAME" -> "checked DESC, file_name ASC"
            "SIZE" -> "checked DESC, file_size DESC"
            else -> "checked DESC, created_at DESC"
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
            where += "(file_name LIKE '%$safe%' OR title LIKE '%$safe%' OR author LIKE '%$safe%' OR title_pinyin LIKE '%$safe%' OR author_pinyin LIKE '%$safe%' OR id IN (SELECT file_id FROM file_notes WHERE content LIKE '%$safe%'))"
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
        page: Int,
        checkedSortToFront: Boolean = false
    ): Flow<List<ScannedFileEntity>> {
        val where = buildFilesWhere(filter, query, runId)
        val checkedPrefix = if (checkedSortToFront) "checked DESC, " else ""
        val orderBy = when (sort) {
            "NAME" -> "${checkedPrefix}file_name ASC"
            "SIZE" -> "${checkedPrefix}file_size DESC"
            else -> "${checkedPrefix}created_at DESC"
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
            where += "(file_name LIKE '%$safe%' OR title LIKE '%$safe%' OR author LIKE '%$safe%' OR title_pinyin LIKE '%$safe%' OR author_pinyin LIKE '%$safe%' OR id IN (SELECT file_id FROM file_notes WHERE content LIKE '%$safe%'))"
        }
        val having = mutableListOf<String>()
        if (minCount > 0) having += "COUNT(*) >= $minCount"
        if (maxCount >= 0) having += "COUNT(*) <= $maxCount"
        // 「含已勾选」：仅保留组内至少有一个已勾选文件的合集（整组仍显示，便于查看勾选情况）
        if (filter == "HAS_CHECKED") having += "SUM(checked) > 0"
        if (excludeNames.isNotEmpty()) {
            val inList = excludeNames.joinToString(",") { "'${it.replace("'", "''")}'" }
            having += "title NOT IN ($inList)"
        }
        val whereSql = where.joinToString(" AND ")
        val havingSql = if (having.isNotEmpty()) " HAVING ${having.joinToString(" AND ")}" else ""
        return whereSql to havingSql
    }

    /** 合集模式：取第 [page] 页（0 基）的分组，每页 [pageSize] 个。[groupSort] 控制排序。 */
    fun groupsPageFlow(
        minCount: Int,
        maxCount: Int,
        excludeNames: List<String>,
        query: String,
        runId: Long,
        pageSize: Int,
        page: Int,
        filter: String = "ALL",
        groupSort: String = "count_desc",
        checkedSortToFront: Boolean = false
    ): Flow<List<NovelGroup>> {
        val (whereSql, havingSql) = buildGroupsClauses(minCount, maxCount, excludeNames, query, runId, filter)
        val limit = pageSize.coerceAtLeast(1)
        val offset = (page.coerceAtLeast(0)) * limit
        val orderBy = buildGroupOrderBy(groupSort, checkedSortToFront)
        val selectExtra = if (groupSort.startsWith("date_")) ", MAX(created_at) AS newest_date" else ""
        val sql = buildString {
            append("SELECT title AS group_title, COUNT(*) AS file_count, SUM(file_size) AS total_size, SUM(checked) AS checked_count")
            append(selectExtra)
            append(" FROM scanned_file WHERE $whereSql GROUP BY title")
            append(havingSql)
            append(" ORDER BY $orderBy")
            append(" LIMIT $limit OFFSET $offset")
        }
        return dao.groupsPageFlow(SimpleSQLiteQuery(sql))
    }

    private fun buildGroupOrderBy(sort: String, checkedSortToFront: Boolean = false): String {
        val base = when (sort) {
            "count_asc"  -> "(checked_count > 0) DESC, (title = '') ASC, file_count ASC, title ASC"
            "size_desc"  -> "(checked_count > 0) DESC, (title = '') ASC, total_size DESC, title ASC"
            "size_asc"   -> "(checked_count > 0) DESC, (title = '') ASC, total_size ASC, title ASC"
            "name_asc"   -> "(title = '') ASC, (checked_count > 0) DESC, title ASC"
            "name_desc"  -> "(title = '') ASC, (checked_count > 0) DESC, title DESC"
            "date_newest"-> "(checked_count > 0) DESC, newest_date DESC, title ASC"
            "date_oldest"-> "(checked_count > 0) DESC, newest_date ASC, title ASC"
            else         -> "(checked_count > 0) DESC, (title = '') ASC, file_count DESC, title ASC"
        }
        return if (checkedSortToFront) {
            base
        } else {
            base.replace("(checked_count > 0) DESC, ", "").replace(", (checked_count > 0) DESC", "")
        }
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

    // ===================== 导出（复用与列表页完全一致的 WHERE/ORDER BY 口径） =====================

    /**
     * 导出用：列表模式一次性取数。[page] < 0 表示导出全量（不加 LIMIT/OFFSET），
     * 否则只取该页，保证「导出当前页」与页面所见完全一致。
     */
    suspend fun exportFilesOnce(
        filter: String,
        query: String,
        sort: String,
        runId: Long,
        pageSize: Int,
        page: Int,
        checkedSortToFront: Boolean = false
    ): List<ScannedFileEntity> {
        val where = buildFilesWhere(filter, query, runId)
        val checkedPrefix = if (checkedSortToFront) "checked DESC, " else ""
        val orderBy = when (sort) {
            "NAME" -> "${checkedPrefix}file_name ASC"
            "SIZE" -> "${checkedPrefix}file_size DESC"
            else -> "${checkedPrefix}created_at DESC"
        }
        val sql = buildString {
            append("SELECT * FROM scanned_file WHERE $where ORDER BY $orderBy")
            if (page >= 0) {
                val limit = pageSize.coerceAtLeast(1)
                append(" LIMIT $limit OFFSET ${page * limit}")
            }
        }
        return dao.filesPageOnce(SimpleSQLiteQuery(sql))
    }

    /**
     * 导出用：合集模式一次性取数。[page] < 0 表示导出全量（不加 LIMIT/OFFSET）。
     */
    suspend fun exportGroupsOnce(
        minCount: Int,
        maxCount: Int,
        excludeNames: List<String>,
        query: String,
        runId: Long,
        pageSize: Int,
        page: Int,
        filter: String = "ALL",
        groupSort: String = "count_desc",
        checkedSortToFront: Boolean = false
    ): List<NovelGroup> {
        val (whereSql, havingSql) = buildGroupsClauses(minCount, maxCount, excludeNames, query, runId, filter)
        val orderBy = buildGroupOrderBy(groupSort, checkedSortToFront)
        // date_* 排序依赖 newest_date 派生列；导出时同样需要 SELECT 出来，否则 ORDER BY 找不到列
        val selectExtra = if (groupSort.startsWith("date_")) ", MAX(created_at) AS newest_date" else ""
        val sql = buildString {
            append("SELECT title AS group_title, COUNT(*) AS file_count, SUM(file_size) AS total_size, SUM(checked) AS checked_count")
            append(selectExtra)
            append(" FROM scanned_file WHERE $whereSql GROUP BY title")
            append(havingSql)
            append(" ORDER BY $orderBy")
            if (page >= 0) {
                val limit = pageSize.coerceAtLeast(1)
                append(" LIMIT $limit OFFSET ${page * limit}")
            }
        }
        return dao.groupsPageOnce(SimpleSQLiteQuery(sql))
    }

    /**
     * 合集模式：按书名分组的分页列表。
     * [minCount]/[maxCount]：合集文件数区间（maxCount<0 表示不限）。
     * [excludeNames]：排除的书名列表。
     * [query]：搜索关键字（匹配书名/作者/文件名）。
     * 空书名合集显示为"未解析"，排序时置底。
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
            where += "(file_name LIKE '%$safe%' OR title LIKE '%$safe%' OR author LIKE '%$safe%' OR title_pinyin LIKE '%$safe%' OR author_pinyin LIKE '%$safe%' OR id IN (SELECT file_id FROM file_notes WHERE content LIKE '%$safe%'))"
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
            append(" ORDER BY (checked_count > 0) DESC, (title = '') ASC, file_count DESC, title ASC")
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
     * 复刻并增强 PC 端 /api/groups/select-duplicates 的"勾选重复"逻辑，只计算应勾选（待删）的 id。
     * 所有判定在【同一文库】内、按 (作者 + 书名) 子分组进行五则规则（与 backend/dup_logic.py 完全一致）：
     *
     * 规则 1（完全相等去重）：(书名 + 作者 + 大小 + 进度) 四字段完全一致（不再比较文件名），
     *     且同组 >= 2 本时，最新(createdAt 最晚，并列取 id 最大)的不勾选，其余全部勾选。
             * 规则 2（纯数字进度对比）：同 (作者+书名) 内，对【有纯数字进度】的文件做比较
             *     （空白进度文件不参与，既不勾选也不保护），进度数字最大的不勾选，其余数字进度文件全部勾选。
     * 规则 3（含中文进度 / 完结特例）：
     *     - 进度含中文(如"完结/连载/断更")的，不勾选（保护状态文件）；
     *     - 若同组存在文件名带『完结』等关键词、且"进度数字最大文件"的大小
     *       小于同组所有含中文进度文件的大小时，该"进度数字最大文件"也要勾选
     *       （说明存在更完整的完结版，部分进度版冗余应删）。
     * 规则 4（最大文件不勾选原则）：已勾选的文件若为本 (作者+书名) 组内文件大小最大者，则不勾选。
     *
     * 返回应勾选的 id 列表，并直接把结果【持久化写入 checked=1】——勾选重复即"勾选"，
     * 与 marked(星标) 完全无关。仅新增勾选、不清空其它已勾选，保证"合并勾选"语义。
     */
    suspend fun selectDuplicateIds(runId: Long, enabledRules: Set<String>? = null): List<Long> {
        val enabled = enabledRules ?: getEnabledDupRuleKeys()
        val rows = dao.getDuplicateRows(runId)
        val userRules = dupRuleDao?.getEnabledUserRules() ?: emptyList()
        // 核心计算委托给纯函数 DupRuleLogic.computeDuplicateChecks（与扫描-勾选重复、一键清理共用同一逻辑）。
        val (allResult, detailLines) = DupRuleLogic.computeDuplicateChecks(rows, enabled, userRules)
        LogUtil.i(
            "Repo",
            "勾选重复 完成 run=$runId enabledRules=$enabled 重复子组=${detailLines.size} 应勾选=${allResult.size} 个"
        )
        if (detailLines.isNotEmpty()) LogUtil.i("Repo", detailLines.joinToString("\n"))
        if (allResult.isNotEmpty()) setCheckedForIds(allResult.toList(), true)
        return allResult.toList()
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
