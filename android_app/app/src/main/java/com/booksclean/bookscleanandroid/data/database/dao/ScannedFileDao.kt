package com.bookscleanandroid.app.data.database.dao

import androidx.paging.PagingSource
import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.RawQuery
import androidx.room.Update
import androidx.sqlite.db.SupportSQLiteQuery
import com.bookscleanandroid.app.data.database.entity.ScannedFileEntity
import com.bookscleanandroid.app.data.database.entity.DuplicateRow
import com.bookscleanandroid.app.data.model.NovelGroup
import kotlinx.coroutines.flow.Flow

@Dao
interface ScannedFileDao {
    @Query("SELECT * FROM scanned_file WHERE id = :id")
    suspend fun getById(id: Long): ScannedFileEntity?

    @Query("SELECT * FROM scanned_file WHERE id IN (:ids)")
    suspend fun getByIds(ids: List<Long>): List<ScannedFileEntity>

    @Query("SELECT * FROM scanned_file WHERE path = :path")
    suspend fun getByPath(path: String): ScannedFileEntity?

    @Query("SELECT * FROM scanned_file WHERE marked = 1")
    suspend fun getMarked(): List<ScannedFileEntity>

    @Query("SELECT COUNT(*) FROM scanned_file")
    fun countFlow(): Flow<Int>

    @Query("SELECT COUNT(*) FROM scanned_file WHERE marked = 1")
    fun countMarkedFlow(): Flow<Int>

    @Query("SELECT COUNT(*) FROM scanned_file WHERE scan_run_id = :runId")
    fun countByRunFlow(runId: Long): Flow<Int>

    /** 同步版：删除文件后重算文库文件数用，避免在 suspend 协程里再 .first()。 */
    @Query("SELECT COUNT(*) FROM scanned_file WHERE scan_run_id = :runId")
    suspend fun countByRunSync(runId: Long): Int

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(files: List<ScannedFileEntity>)

    @Update
    suspend fun update(file: ScannedFileEntity)

    @Query("UPDATE scanned_file SET marked = :m WHERE id = :id")
    suspend fun setMarked(id: Long, m: Int)

    @Query("UPDATE scanned_file SET marked = 0 WHERE scan_run_id = :runId")
    suspend fun clearMarked(runId: Long)

    @Query("UPDATE scanned_file SET marked = 1 WHERE id IN (:ids)")
    suspend fun markIds(ids: List<Long>)

    @Query("UPDATE scanned_file SET checked = :c WHERE id = :id")
    suspend fun setChecked(id: Long, c: Int)

    @Query("UPDATE scanned_file SET checked = :c WHERE id IN (:ids)")
    suspend fun setCheckedForIds(ids: List<Long>, c: Int)

    @Query("UPDATE scanned_file SET checked = 0 WHERE scan_run_id = :runId")
    suspend fun clearChecked(runId: Long)

    @Query("SELECT id FROM scanned_file WHERE scan_run_id = :runId AND checked = 1")
    suspend fun getCheckedIds(runId: Long): List<Long>

    @Query("SELECT COUNT(*) FROM scanned_file WHERE scan_run_id = :runId AND checked = 1")
    fun checkedCountFlow(runId: Long): Flow<Int>

    @Query("DELETE FROM scanned_file WHERE id IN (:ids)")
    suspend fun deleteByIds(ids: List<Long>)

    @Query("DELETE FROM scanned_file WHERE scan_run_id = :runId")
    suspend fun deleteByRunId(runId: Long)

    /**
     * 跨文库同步删除：在 APP 内删除文件（含源文件）时，同一物理文件可能出现在多个文库中，
     * 需要把所有文库里记录该 path 的行一并删除。先收集待删 id 对应的 path 与受影响文库，
     * 再按 path 删除全部匹配行，最后重算受影响文库的 file_count。
     * 跨文库同步删除的辅助查询（编排逻辑放在 FileRepository.deleteFilesSynced）。
     */
    @Query("SELECT DISTINCT path FROM scanned_file WHERE id IN (:ids)")
    suspend fun getPathsByIds(ids: List<Long>): List<String>

    @Query("SELECT DISTINCT scan_run_id FROM scanned_file WHERE path = :path")
    suspend fun getRunsByPath(path: String): List<Long>

    @Query("DELETE FROM scanned_file WHERE path = :path")
    suspend fun deleteByPath(path: String)

    @Query("UPDATE scan_run SET file_count = :count WHERE id = :runId")
    suspend fun setRunFileCount(runId: Long, count: Int)

    @Query("DELETE FROM scanned_file")
    suspend fun deleteAll()

    /**
     * 按“书名 + 作者”相同勾选重复（文件名解析结果）。每组保留 id 最小的一条，其余标记。
     */
    @Query("""
        UPDATE scanned_file SET marked = 1
        WHERE scan_run_id = :runId
          AND title != ''
          AND (lower(trim(title)) || '|' || lower(trim(COALESCE(author, '')))) IN (
              SELECT lower(trim(title)) || '|' || lower(trim(COALESCE(author, '')))
              FROM scanned_file WHERE scan_run_id = :runId AND title != ''
              GROUP BY lower(trim(title)) || '|' || lower(trim(COALESCE(author, '')))
              HAVING COUNT(*) > 1
          )
          AND id NOT IN (
              SELECT MIN(id) FROM scanned_file WHERE scan_run_id = :runId AND title != ''
              GROUP BY lower(trim(title)) || '|' || lower(trim(COALESCE(author, '')))
          )
    """)
    suspend fun markDuplicatesByNameSql(runId: Long): Int

    /**
     * 按内容哈希相同、但修改时间更早的文件标记。
     * 同一 content_hash 组内仅保留“最新修改时间”的那一条（file_date 优先，回退 created_at，相同则取最大 id）不标记，
     * 其余更早的全部标记 marked=1。仅作用于已计算哈希（content_hash <> ''）的文件。
     */
    @Query("""
        UPDATE scanned_file
        SET marked = 1
        WHERE scan_run_id = :runId
          AND content_hash <> ''
          AND id NOT IN (
            SELECT k.id FROM (
                SELECT content_hash,
                       MAX(COALESCE(file_date, created_at)) AS maxdate,
                       MAX(id) AS keep_id
                FROM scanned_file
                WHERE scan_run_id = :runId AND content_hash <> ''
                GROUP BY content_hash
            ) g
            JOIN scanned_file k
              ON k.scan_run_id = :runId
             AND k.content_hash = g.content_hash
             AND COALESCE(k.file_date, k.created_at) = g.maxdate
             AND k.id = g.keep_id
          )
    """)
    suspend fun markDuplicatesByHashSql(runId: Long): Int

    /**
     * 按内容哈希相同、但修改时间更早的文件勾选。逻辑同 markDuplicatesByHashSql，仅置 checked=1。
     */
    @Query("""
        UPDATE scanned_file
        SET checked = 1
        WHERE scan_run_id = :runId
          AND content_hash <> ''
          AND id NOT IN (
            SELECT k.id FROM (
                SELECT content_hash,
                       MAX(COALESCE(file_date, created_at)) AS maxdate,
                       MAX(id) AS keep_id
                FROM scanned_file
                WHERE scan_run_id = :runId AND content_hash <> ''
                GROUP BY content_hash
            ) g
            JOIN scanned_file k
              ON k.scan_run_id = :runId
             AND k.content_hash = g.content_hash
             AND COALESCE(k.file_date, k.created_at) = g.maxdate
             AND k.id = g.keep_id
          )
    """)
    suspend fun checkDuplicatesByHashSql(runId: Long): Int

    /** 该文库是否已扫描内容哈希（存在非空 content_hash 的文件）。 */
    @Query("SELECT COUNT(*) FROM scanned_file WHERE scan_run_id = :runId AND content_hash <> ''")
    suspend fun hasContentHash(runId: Long): Int

    /**
     * 分页查询：WHERE/ORDER BY 由 Repository 依据筛选/搜索/排序动态拼装。
     * 返回 PagingSource 让 Paging3 以 LIMIT/OFFSET 分批加载，避免一次性把 10w 行读进内存。
     */
    @RawQuery(observedEntities = [ScannedFileEntity::class])
    fun pagedRaw(query: SupportSQLiteQuery): PagingSource<Int, ScannedFileEntity>

    /**
     * 合集模式：按书名（title）分组的分页查询。SQL 由 Repository 依据数量区间/排除/搜索动态拼装
     * （GROUP BY title + HAVING + ORDER BY），返回分组头（书名、文件数、总大小）。
     */
    @RawQuery(observedEntities = [ScannedFileEntity::class])
    fun pagedGroupsRaw(query: SupportSQLiteQuery): PagingSource<Int, NovelGroup>

    // ===================== 真·页码分页（LIMIT/OFFSET，Flow 自动刷新） =====================
    /**
     * 列表模式：取「当前页」这一批文件。SQL（含 WHERE/ORDER BY/LIMIT/OFFSET）由 Repository 拼装。
     * 返回 Flow：底层 scanned_file 表增删改（标记/删除等）时 Room 会自动重新发射当前页，无需手动刷新。
     */
    @RawQuery(observedEntities = [ScannedFileEntity::class])
    fun filesPageFlow(query: SupportSQLiteQuery): Flow<List<ScannedFileEntity>>

    /** 列表模式：符合当前筛选/搜索条件的总条数（用于计算总页数）。表变化时自动重发。 */
    @RawQuery(observedEntities = [ScannedFileEntity::class])
    fun filesCountFlow(query: SupportSQLiteQuery): Flow<Int>

    /** 合集模式：取「当前页」这一批分组（书名/文件数/总大小）。 */
    @RawQuery(observedEntities = [ScannedFileEntity::class])
    fun groupsPageFlow(query: SupportSQLiteQuery): Flow<List<NovelGroup>>

    /** 合集模式：符合当前区间/排除/搜索条件的分组总数（用于计算总页数）。 */
    @RawQuery(observedEntities = [ScannedFileEntity::class])
    fun groupsCountFlow(query: SupportSQLiteQuery): Flow<Int>

    // ===================== 导出用一次性查询（非 Flow，避免导出时订阅表变化） =====================
    /** 列表模式导出：一次性取一批文件（SQL 含 WHERE/ORDER BY/LIMIT/OFFSET，由 Repository 拼装）。 */
    @RawQuery
    suspend fun filesPageOnce(query: SupportSQLiteQuery): List<ScannedFileEntity>

    /** 合集模式导出：一次性取一批分组。 */
    @RawQuery
    suspend fun groupsPageOnce(query: SupportSQLiteQuery): List<NovelGroup>

    /** 取某个合集（书名）内的全部文件，供展开时懒加载。空书名传 "" 匹配未解析组。
     *  [marked]：为 null 不过滤；为 1 仅已标记（已勾选）；为 0 仅未标记。 */
    @Query("""
        SELECT * FROM scanned_file
        WHERE scan_run_id = :runId AND title = :title
          AND (:marked IS NULL OR marked = :marked)
          AND (:checked IS NULL OR checked = :checked)
        ORDER BY file_name ASC
    """)
    suspend fun getFilesByTitle(runId: Long, title: String, marked: Int? = null, checked: Int? = null): List<ScannedFileEntity>

    /**
     * 复刻 PC 端“勾选重复”：取某文库全部文件的
     * (id, 文件名, 书名, 作者, 进度, 大小, 创建时间, 文件修改时间) 投影，
     * 由 Repository 在 Kotlin 端按 (书名+作者+大小+进度) 四元组分组（不再比较文件名）、
     * 比较文件修改时间后计算待删 id。
     * 别名 file_name AS fileName、file_size AS fileSize、created_at AS createdAt、file_date AS fileDate 以匹配字段名。
     */
    @Query("""
        SELECT s.id, s.file_name AS fileName, s.title, s.author, s.progress,
               COALESCE(s.source, '') AS source,
               s.file_size AS fileSize, s.created_at AS createdAt,
               COALESCE(s.file_date, 0) AS fileDate,
               COALESCE(s.content_hash, '') AS contentHash
        FROM scanned_file s
        WHERE s.scan_run_id = :runId
    """)
    suspend fun getDuplicateRows(runId: Long): List<DuplicateRow>
}
