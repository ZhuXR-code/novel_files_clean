package com.bookscleanandroid.app.data.database.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import com.bookscleanandroid.app.data.database.entity.ScanRunEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ScanRunDao {
    @Insert
    suspend fun insert(run: ScanRunEntity): Long

    @Update
    suspend fun update(run: ScanRunEntity)

    @Query("DELETE FROM scan_run WHERE id = :id")
    suspend fun deleteById(id: Long)

    @Query("UPDATE scan_run SET file_count = :count WHERE id = :id")
    suspend fun setFileCount(id: Long, count: Int)

    /** 文库列表（按扫描时间倒序，最新在前）。 */
    @Query("SELECT * FROM scan_run ORDER BY created_at DESC")
    fun getAllRuns(): Flow<List<ScanRunEntity>>

    @Query("SELECT * FROM scan_run WHERE id = :id")
    suspend fun getById(id: Long): ScanRunEntity?

    /**
     * 将多个文库合并为一个新文库。
     * 事务内完成：
     *   1) 创建新文库（newName 命名，folder_name 记录来源数量）；
     *   2) 把所有源文库的文件复制为新文库下的新行（保留 marked/checked/title/author
     *      等全部状态），跨文库相同 path 的文件由 UNIQUE(path, scan_run_id) 去重，
     *      每个 path 保留一条（ON CONFLICT DO NOTHING）；
     *   3) 回写新文库 file_count；
     *   4) 原文库保留，仅新增一个合并文库（不删除源文库）。
     * 返回新建文库的 id。
     *
     * 维护提示：INSERT...SELECT 的列列表必须与 scanned_file 当前列顺序一致，
     * 日后新增列时需同步此处，否则会触发列数不匹配错误。
     */
    @Transaction
    suspend fun mergeRuns(sourceIds: List<Long>, newName: String, now: Long): Long {
        // 继承第一个源文库的安全作用域书签（folderUri），否则合并后预览/删除/打开等操作均无法访问文件
        val firstSource = getById(sourceIds.first())
        val newId = insert(
            ScanRunEntity(
                name = newName,
                folderUri = firstSource?.folderUri ?: "",
                folderName = firstSource?.folderName ?: "合并自 ${sourceIds.size} 个文库",
                fileTypes = "txt",
                createdAt = now
            )
        )
        copyFilesToRun(newId, sourceIds)
        val count = countFilesInRun(newId)
        setFileCount(newId, count)
        // 保留原文库：仅新增一个合并文库，不再删除源文库及其文件
        return newId
    }

    /**
     * 把 sourceIds 下的所有文件复制为新文库 newId 下的新行。
     * 不拷贝自增 id；相同 (path, newId) 冲突时忽略，实现跨文库 path 去重。
     */
    @Query(
        """
        INSERT INTO scanned_file (
            scan_run_id, path, file_name, file_size, title, author, progress, source,
            encoding, title_pinyin, author_pinyin, content_hash, ext, marked, checked,
            created_at, file_date
        )
        SELECT :newId, path, file_name, file_size, title, author, progress, source,
            encoding, title_pinyin, author_pinyin, content_hash, ext, marked, checked,
            created_at, file_date
        FROM scanned_file
        WHERE scan_run_id IN (:sourceIds)
        ON CONFLICT(path, scan_run_id) DO NOTHING
        """
    )
    suspend fun copyFilesToRun(newId: Long, sourceIds: List<Long>)

    @Query("SELECT COUNT(*) FROM scanned_file WHERE scan_run_id = :runId")
    suspend fun countFilesInRun(runId: Long): Int

    @Query("DELETE FROM scanned_file WHERE scan_run_id IN (:ids)")
    suspend fun deleteFilesByRunIds(ids: List<Long>)

    @Query("DELETE FROM scan_run WHERE id IN (:ids)")
    suspend fun deleteRunsByIds(ids: List<Long>)
}
