package com.bookscleanandroid.app.data.repository

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bookscleanandroid.app.data.database.AppDatabase
import com.bookscleanandroid.app.data.database.entity.ScannedFileEntity
import com.bookscleanandroid.app.data.database.entity.ScanRunEntity
import com.bookscleanandroid.app.data.repository.FileRepository
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * 删除文件跨文库同步测试（Instrumented，运行在 MuMu 模拟器）。
 *
 * 核心语义：在 APP 内删除文件（含源文件）时，同一物理文件可能出现在多个文库中，
 * 需要把所有文库里记录该 path 的行一并删除，并重算受影响文库的 file_count。
 * 这里直接验证 FileRepository.deleteFilesSynced 的底层链路（DAO 方法）。
 */
@RunWith(AndroidJUnit4::class)
class DeleteSyncTest {

    private lateinit var db: AppDatabase

    @Before
    fun setUp() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            AppDatabase::class.java
        ).allowMainThreadQueries().build()
    }

    @After
    fun tearDown() {
        db.close()
    }

    private fun insertRun(name: String): Long = runBlocking {
        db.scanRunDao().insert(
            ScanRunEntity(name = name, folderName = "测试目录", fileTypes = "txt", createdAt = 1L)
        )
    }

    private fun file(runId: Long, path: String, name: String) = ScannedFileEntity(
        path = path, fileName = name, fileSize = 100L, title = "书名", author = "作者",
        progress = "10", source = "", encoding = "", titlePinyin = "", authorPinyin = "",
        contentHash = "", ext = "txt", marked = 0, checked = 0,
        scanRunId = runId, createdAt = 1L, fileDate = 1L
    )

    @Test
    fun deleteInOneLibrary_removesRecordFromAllLibrariesByPath() { // 删除某文库中的文件，其他文库同名 path 记录同步删除
        val runA = insertRun("文库A")
        val runB = insertRun("文库B")
        val runC = insertRun("文库C")
        runBlocking {
            db.scannedFileDao().insertAll(
                listOf(
                    file(runA, "/shared/x.txt", "x.txt"),  // 三库都有
                    file(runB, "/shared/x.txt", "x.txt"),
                    file(runC, "/shared/x.txt", "x.txt"),
                    file(runA, "/a/only.txt", "only.txt"), // A 独有
                    file(runB, "/b/other.txt", "other.txt"), // B 独有
                )
            )
        }

        // 在文库A 内删除 x.txt（通过按 path 同步删除）
        val toDelete = runBlocking { db.scannedFileDao().getByPath("/shared/x.txt") }
        val idInA = toDelete!!.id
        val repo = FileRepository(db.scannedFileDao(), db.scanRunDao(), db.keywordReplaceDao())
        runBlocking { repo.deleteFilesSynced(listOf(idInA)) }

        runBlocking {
            // 三库中 x.txt 全部消失
            assertEquals(0, db.scannedFileDao().getRunsByPath("/shared/x.txt").size)
            assertEquals(null, db.scannedFileDao().getByPath("/shared/x.txt"))
            // A/B 独有文件不受影响
            assertEquals(1, db.scanRunDao().countFilesInRun(runA))
            assertEquals(1, db.scanRunDao().countFilesInRun(runB))
            assertEquals(0, db.scanRunDao().countFilesInRun(runC))
            // 受影响文库 file_count 重算正确
            assertEquals(1, db.scanRunDao().getById(runA)!!.fileCount)
            assertEquals(1, db.scanRunDao().getById(runB)!!.fileCount)
            assertEquals(0, db.scanRunDao().getById(runC)!!.fileCount)
        }
    }

    @Test
    fun deleteUniqueFile_onlyRemovesFromOwningLibrary() { // 删除只存在于一个文库的文件，不影响其他文库
        val runA = insertRun("文库A")
        val runB = insertRun("文库B")
        runBlocking {
            db.scannedFileDao().insertAll(
                listOf(
                    file(runA, "/a/only.txt", "only.txt"),
                    file(runB, "/b/other.txt", "other.txt"),
                )
            )
        }

        val toDelete = runBlocking { db.scannedFileDao().getByPath("/a/only.txt") }!!
        val repo = FileRepository(db.scannedFileDao(), db.scanRunDao(), db.keywordReplaceDao())
        runBlocking { repo.deleteFilesSynced(listOf(toDelete.id)) }

        runBlocking {
            // runA 的文件被删、记录消失，file_count 重算为 0
            assertEquals(0, db.scanRunDao().countFilesInRun(runA))
            assertEquals(0, db.scanRunDao().getById(runA)!!.fileCount)
            assertEquals(null, db.scannedFileDao().getByPath("/a/only.txt"))
            // 仅存在于 runA 的文件被删，runB 不受影响：其文件记录仍在（file_count 未参与本次删除故保持种子值，只验证记录还在）
            assertEquals("/b/other.txt", db.scannedFileDao().getByPath("/b/other.txt")?.path)
        }
    }

    @Test
    fun deleteEmptyList_isNoop() {
        val repo = FileRepository(db.scannedFileDao(), db.scanRunDao(), db.keywordReplaceDao())
        runBlocking { repo.deleteFilesSynced(emptyList()) }
        // 不抛异常即通过
    }
}
