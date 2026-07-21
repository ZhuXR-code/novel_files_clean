package com.filescanner.app.util

import org.junit.Assert.assertEquals
import org.junit.Test

class LibraryLogicTest {

    // ===================== computePageCount =====================
    @Test
    fun `总页数 总数为0 至少1页`() {
        assertEquals(1, LibraryLogic.computePageCount(0, 100))
    }

    @Test
    fun `总页数 恰好整除`() {
        assertEquals(1, LibraryLogic.computePageCount(100, 100))
        assertEquals(2, LibraryLogic.computePageCount(200, 100))
    }

    @Test
    fun `总页数 不整除 向上取整`() {
        assertEquals(2, LibraryLogic.computePageCount(101, 100))
        assertEquals(2, LibraryLogic.computePageCount(199, 100))
        assertEquals(3, LibraryLogic.computePageCount(250, 100))
    }

    @Test
    fun `总页数 单条 大页大小`() {
        assertEquals(1, LibraryLogic.computePageCount(1, 2000))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `总页数 pageSize非法 抛异常`() {
        LibraryLogic.computePageCount(10, 0)
    }

    // ===================== parseExcludeNames =====================
    @Test
    fun `排除名 空串返回空表`() {
        assertEquals(emptyList<String>(), LibraryLogic.parseExcludeNames(""))
        assertEquals(emptyList<String>(), LibraryLogic.parseExcludeNames("   "))
    }

    @Test
    fun `排除名 单书名`() {
        assertEquals(listOf("都市奇缘"), LibraryLogic.parseExcludeNames("都市奇缘"))
    }

    @Test
    fun `排除名 逗号分隔 去空白`() {
        assertEquals(listOf("都市奇缘", "江湖路远"), LibraryLogic.parseExcludeNames("都市奇缘, 江湖路远"))
    }

    @Test
    fun `排除名 换行分隔`() {
        assertEquals(listOf("都市奇缘", "江湖路远"), LibraryLogic.parseExcludeNames("都市奇缘\n江湖路远"))
    }

    @Test
    fun `排除名 逗号换行混合`() {
        assertEquals(listOf("a", "b", "c", "d"), LibraryLogic.parseExcludeNames("a, b\n c ,d"))
    }

    @Test
    fun `排除名 尾随分隔符不产空项`() {
        assertEquals(listOf("x"), LibraryLogic.parseExcludeNames("x,"))
    }

    // ===================== adjustPage =====================
    @Test
    fun `页码回退 首页`() {
        assertEquals(0, LibraryLogic.adjustPage(0, 1))
    }

    @Test
    fun `页码回退 越界夹到最后页`() {
        assertEquals(2, LibraryLogic.adjustPage(5, 3)) // 最后一页索引=2
    }

    @Test
    fun `页码回退 负值夹到0`() {
        assertEquals(0, LibraryLogic.adjustPage(-1, 3))
    }

    @Test
    fun `页码回退 范围内不变`() {
        assertEquals(2, LibraryLogic.adjustPage(2, 3))
    }

    @Test
    fun `页码回退 pageCount为0时防御`() {
        assertEquals(0, LibraryLogic.adjustPage(3, 0))
    }
}
