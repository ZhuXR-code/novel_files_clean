package com.filescanner.app.data.database.dao

import androidx.paging.PagingSource
import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.RawQuery
import androidx.room.Update
import androidx.sqlite.db.SupportSQLiteQuery
import com.filescanner.app.data.database.entity.ScannedFileEntity
import com.filescanner.app.data.database.entity.DuplicateRow
import com.filescanner.app.data.model.NovelGroup
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
     * (id, 文件名, 书名, 作者, 进度, 大小, 创建时间) 投影，
     * 由 Repository 在 Kotlin 端按 (书名+作者+大小+进度) 四元组分组（不再比较文件名）、
     * 比较创建时间后计算待删 id。
     * 别名 file_name AS fileName、file_size AS fileSize、created_at AS createdAt 以匹配字段名。
     */
    @Query("""
        SELECT s.id, s.file_name AS fileName, s.title, s.author, s.progress,
               COALESCE(s.source, '') AS source,
               s.file_size AS fileSize, s.created_at AS createdAt
        FROM scanned_file s
        WHERE s.scan_run_id = :runId
    """)
    suspend fun getDuplicateRows(runId: Long): List<DuplicateRow>
}
