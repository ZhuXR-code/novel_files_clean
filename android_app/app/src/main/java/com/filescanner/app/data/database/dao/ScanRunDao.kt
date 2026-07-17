package com.filescanner.app.data.database.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import com.filescanner.app.data.database.entity.ScanRunEntity
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
}
