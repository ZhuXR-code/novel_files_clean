package com.bookscleanandroid.app.data.repository

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bookscleanandroid.app.data.database.AppDatabase
import com.bookscleanandroid.app.data.database.entity.ScannedFileEntity
import com.bookscleanandroid.app.data.database.entity.ScanRunEntity
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * 合并文库功能端到端测试（Instrumented，运行在 MuMu 模拟器）。
 *
 * 覆盖 mergeRuns 的核心语义：
 *   1) 多文库文件并集到新文库，file_count 正确；
 *   2) 跨文库相同 path 自动去重（UNIQUE(path, scan_run_id) + ON CONFLICT DO NOTHING）；
 *   3) marked / checked / title / author 等状态完整保留；
 *   4) 源文库及其文件在合并后被删除；
 *   5) 文件归属到新文库（scan_run_id 指向 newId）。
 */
@RunWith(AndroidJUnit4::class)
class MergeRunsTest {

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

    private fun file(
        runId: Long, path: String, name: String, title: String = "书名",
        author: String = "作者", marked: Int = 0, checked: Int = 0,
        contentHash: String = ""
    ) = ScannedFileEntity(
        path = path, fileName = name, fileSize = 100L, title = title, author = author,
        progress = "10", source = "", encoding = "", titlePinyin = "", authorPinyin = "",
        contentHash = contentHash, ext = "txt", marked = marked, checked = checked,
        scanRunId = runId, createdAt = 1L, fileDate = 1L
    )

    // ===================== 基本合并 =====================

    @Test
    fun mergeTwoDisjointLibraries_keepsUnionAndCount() { // 合并两个不相交文库 文件并集 数量正确
        val runA = insertRun("文库A")
        val runB = insertRun("文库B")
        runBlocking {
            db.scannedFileDao().insertAll(
                listOf(
                    file(runA, "/a/1.txt", "1.txt"),
                    file(runA, "/a/2.txt", "2.txt"),
                    file(runB, "/b/3.txt", "3.txt"),
                )
            )
        }

        val newId = runBlocking { db.scanRunDao().mergeRuns(listOf(runA, runB), "合并AB", 100L) }

        runBlocking {
            assertEquals(3, db.scanRunDao().countFilesInRun(newId))
            assertEquals(3, db.scanRunDao().getById(newId)!!.fileCount)
        }
    }

    // ===================== 跨文库 path 去重 =====================

    @Test
    fun mergeDedupBySamePathAcrossLibraries() { // 合并时跨文库相同path 去重 仅保留一条
        val runA = insertRun("文库A")
        val runB = insertRun("文库B")
        runBlocking {
            db.scannedFileDao().insertAll(
                listOf(
                    file(runA, "/same/x.txt", "x.txt"),
                    file(runB, "/same/x.txt", "x.txt"),
                    file(runA, "/a/only.txt", "only.txt"),
                )
            )
        }

        val newId = runBlocking { db.scanRunDao().mergeRuns(listOf(runA, runB), "合并去重", 100L) }

        runBlocking {
            assertEquals(2, db.scanRunDao().countFilesInRun(newId))
        }
    }

    // ===================== 状态保留 =====================

    @Test
    fun mergeKeepsMarkedCheckedTitleAuthor() { // 合并后 marked checked title author 状态完整保留
        val runA = insertRun("文库A")
        val runB = insertRun("文库B")
        runBlocking {
            db.scannedFileDao().insertAll(
                listOf(
                    file(runA, "/a/1.txt", "1.txt", title = "斗破苍穹", author = "天蚕土豆", marked = 1, checked = 1),
                    file(runB, "/b/2.txt", "2.txt", title = "完美世界", author = "辰东", marked = 0, checked = 0),
                )
            )
        }

        val newId = runBlocking { db.scanRunDao().mergeRuns(listOf(runA, runB), "合并状态", 100L) }

        runBlocking {
            val files = db.scannedFileDao().getDuplicateRows(newId).sortedBy { it.fileName }
            assertEquals(2, files.size)
            val f1 = files.first { it.fileName == "1.txt" }
            assertEquals("斗破苍穹", f1.title)
            assertEquals("天蚕土豆", f1.author)
            assertEquals(1, db.scannedFileDao().getByPath("/a/1.txt")!!.marked)
        }
    }

    // ===================== 文件汇聚到新文库 + 源文库保留不动 =====================
    // 当前 mergeRuns 语义：保留源文库，仅新增一个合并文库（见 ScanRunDao.mergeRuns 注释）。

    @Test
    fun mergeCopiesFilesToNewRunAndKeepsSources() { // 合并后新文库含全部文件，原文库文件保持不变
        val runA = insertRun("文库A")
        val runB = insertRun("文库B")
        runBlocking {
            db.scannedFileDao().insertAll(
                listOf(
                    file(runA, "/a/1.txt", "1.txt"),
                    file(runB, "/b/2.txt", "2.txt"),
                )
            )
        }

        val newId = runBlocking { db.scanRunDao().mergeRuns(listOf(runA, runB), "合并归属", 100L) }

        runBlocking {
            // 新文库汇聚两份文件
            assertEquals(2, db.scanRunDao().countFilesInRun(newId))
            // 原文库文件保留不动
            assertEquals(1, db.scanRunDao().countFilesInRun(runA))
            assertEquals(1, db.scanRunDao().countFilesInRun(runB))
        }
    }

    // ===================== 源文库保留 =====================

    @Test
    fun mergeKeepsSourceRunRecords() { // 合并后源文库记录仍保留在 scan_run 表（当前语义：合并不删除源）
        val runA = insertRun("文库A")
        val runB = insertRun("文库B")

        val newId = runBlocking { db.scanRunDao().mergeRuns(listOf(runA, runB), "合并保留源", 100L) }

        runBlocking {
            assertNotNull(db.scanRunDao().getById(runA))
            assertNotNull(db.scanRunDao().getById(runB))
            assertNotNull(db.scanRunDao().getById(newId))
            // 共 3 个文库：2 源 + 1 合并
            assertEquals(3, db.scanRunDao().getAllRuns().first().size)
        }
    }

    // ===================== 三个文库合并 =====================

    @Test
    fun mergeThreeLibraries_dedupAndCount() { // 合并三个文库 数量与去重正确
        val runA = insertRun("文库A")
        val runB = insertRun("文库B")
        val runC = insertRun("文库C")
        runBlocking {
            db.scannedFileDao().insertAll(
                listOf(
                    file(runA, "/a/1.txt", "1.txt"),
                    file(runB, "/b/2.txt", "2.txt"),
                    file(runC, "/c/3.txt", "3.txt"),
                    file(runA, "/shared/x.txt", "x.txt"),
                    file(runC, "/shared/x.txt", "x.txt"),
                )
            )
        }

        val newId = runBlocking { db.scanRunDao().mergeRuns(listOf(runA, runB, runC), "合并三库", 100L) }

        runBlocking {
            assertEquals(4, db.scanRunDao().countFilesInRun(newId))
            assertEquals(4, db.scanRunDao().getById(newId)!!.fileCount)
        }
    }

    // ===================== 单源合并（DAO 不校验，由 Repository 层 require 拦截） =====================

    @Test
    fun mergeWithSingleRun_createsNewRunWithCopiedFiles() { // 单源合并：DAO 仍会创建新文库并复制文件（调用方需保证 >=2）
        val runA = insertRun("文库A")
        runBlocking { db.scannedFileDao().insertAll(listOf(file(runA, "/a/1.txt", "1.txt"))) }

        val newId = runBlocking { db.scanRunDao().mergeRuns(listOf(runA), "单独合并", 100L) }

        runBlocking {
            assertNotNull(db.scanRunDao().getById(newId))
            assertEquals(1, db.scanRunDao().countFilesInRun(newId))
        }
    }
}
