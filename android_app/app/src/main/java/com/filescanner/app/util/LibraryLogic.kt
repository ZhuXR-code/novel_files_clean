package com.filescanner.app.util

/**
 * 列表/合集分页相关的纯计算，从 LibraryViewModel 中提取，便于 JUnit 单测，且与 Android 运行时无关。
 * 行为与原内联实现完全一致，仅做位置重构。
 */
object LibraryLogic {

    /**
     * 计算总页数：至少 1 页（即使总数为 0，也返回 1，使 UI 可显示“第 1 页 / 共 1 页”）。
     * 等价于 ((total + pageSize - 1) / pageSize).coerceAtLeast(1)。
     */
    fun computePageCount(total: Int, pageSize: Int): Int {
        require(pageSize > 0) { "pageSize 必须 > 0，实际 $pageSize" }
        return ((total + pageSize - 1) / pageSize).coerceAtLeast(1)
    }

    /**
     * 解析合集“排除书名”输入：按逗号/换行切分，去空白、丢弃空项。
     * 等价于 raw.split(Regex("[,\n]+")).map { it.trim() }.filter { it.isNotEmpty() }。
     */
    fun parseExcludeNames(raw: String): List<String> {
        return raw.split(Regex("[,\n]+")).map { it.trim() }.filter { it.isNotEmpty() }
    }

    /**
     * 当前页码越界回退：若 page 超过最后一页（pageCount-1），夹到最后一页；小于 0 夹到 0。
     * 等价于 page.coerceIn(0, (pageCount - 1).coerceAtLeast(0))。
     */
    fun adjustPage(page: Int, pageCount: Int): Int {
        return page.coerceIn(0, (pageCount - 1).coerceAtLeast(0))
    }
}
