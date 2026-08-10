package com.bookscleanandroid.app.data.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.bookscleanandroid.app.data.database.entity.FileNoteEntity
import kotlinx.coroutines.flow.Flow

/**
 * 文件备注 DAO。
 *
 * 去重策略（区分大小写）：
 * - 建表时 file_id + content 唯一索引使用默认 BINARY 排序（SQLite 默认即区分大小写），
 *   故 INSERT 重复内容会触发 OnConflictStrategy.ABORT，由上层捕获返回失败。
 * - "A" 与 "a" 视为不同内容，可同时存在于同一文件下。
 */
@Dao
interface FileNoteDao {

    /** 取某文件全部备注（按创建时间升序，保持用户添加顺序）。 */
    @Query("SELECT * FROM file_notes WHERE file_id = :fileId ORDER BY created_at ASC, id ASC")
    fun getNotesByFile(fileId: Long): Flow<List<FileNoteEntity>>

    /** 取某文件全部备注（一次性，非 Flow，供合并书库复制用）。 */
    @Query("SELECT * FROM file_notes WHERE file_id = :fileId ORDER BY created_at ASC, id ASC")
    suspend fun getNotesByFileOnce(fileId: Long): List<FileNoteEntity>

    /** 新增备注，重复内容（区分大小写）抛冲突，由仓库层捕获返回 false。 */
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(note: FileNoteEntity): Long

    @Update
    suspend fun update(note: FileNoteEntity)

    @Delete
    suspend fun delete(note: FileNoteEntity)

    @Query("DELETE FROM file_notes WHERE id = :noteId")
    suspend fun deleteById(noteId: Long)

    @Query("DELETE FROM file_notes WHERE file_id = :fileId")
    suspend fun deleteByFile(fileId: Long)

    /** 取某文件全部备注（供合集/合并书库复制），返回批量列表。 */
    @Query("SELECT * FROM file_notes WHERE file_id IN (:fileIds)")
    suspend fun getNotesByFilesOnce(fileIds: List<Long>): List<FileNoteEntity>

    /** 批量写入备注，重复 content（区分大小写）静默忽略（用于合并书库复制去重）。 */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertIgnore(notes: List<FileNoteEntity>)

    /**
     * 合并书库时复制备注（高性能单语句版本，避免 20w 级别下巨型 IN 与全量内存映射）。
     *
     * 通过三层 JOIN 在数据库内部完成「源备注 -> 新文件」的按 path 重映射，
     * 重复内容由 file_notes 唯一索引 (file_id, content) 自动去重（区分大小写，INSERT OR IGNORE）。
     *
     * - 源文库 ids 在 IN (...) 中，但数量仅为用户选择的文库数（通常个位数），不存在参数上限问题；
     * - 新文库文件虽可能达 20w，但 JOIN 走 path 索引、全部在 DB 内部完成，不进应用内存；
     * - 返回受影响行数（忽略重复后实际插入的备注数）。
     */
    @Query("""
        INSERT OR IGNORE INTO file_notes (file_id, content, created_at)
        SELECT nf.id, src.content, src.created_at
        FROM scanned_file nf
        JOIN scanned_file sf ON sf.path = nf.path AND sf.scan_run_id IN (:sourceRunIds)
        JOIN file_notes src ON src.file_id = sf.id
        WHERE nf.scan_run_id = :newRunId
    """)
    suspend fun copyNotesOnMerge(newRunId: Long, sourceRunIds: List<Long>): Int
}
