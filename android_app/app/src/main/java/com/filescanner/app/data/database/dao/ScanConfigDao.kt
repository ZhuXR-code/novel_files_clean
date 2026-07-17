package com.filescanner.app.data.database.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.filescanner.app.data.database.entity.ScanConfigEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ScanConfigDao {
    /** 所有配置，按创建时间倒序。返回 Flow 以便界面实时刷新。 */
    @Query("SELECT * FROM scan_config ORDER BY id DESC")
    fun getAll(): Flow<List<ScanConfigEntity>>

    @Query("SELECT * FROM scan_config WHERE id = :id")
    suspend fun getById(id: Long): ScanConfigEntity?

    /** REPLACE：新建（id=0）插入，编辑（带原 id）则替换，一条语句即可 upsert。 */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(config: ScanConfigEntity): Long

    @Query("DELETE FROM scan_config WHERE id = :id")
    suspend fun deleteById(id: Long)
}
