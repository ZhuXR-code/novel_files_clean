package com.filescanner.app.util

/**
 * 合集模式「勾选重复」核心逻辑的独立测试。
 *
 * 本文件【逐字移植】自 FileRepository.selectDuplicateIds（含其五个私有辅助函数），
 * 仅去掉了 Room/DAO 依赖（getDuplicateRows 改由入参提供、去掉 setCheckedForIds 持久化、
 * 去掉 LogUtil 日志），算法本身与 APP 运行态完全一致。
 */
data class DuplicateRow(
    val id: Long,
    val fileName: String,
    val fileSize: Long,
    val title: String,
    val author: String,
    val progress: String,
    val createdAt: String
)

private val COMPLETION_KW = listOf("完结", "完本", "全本", "全集", "完整", "全套", "全集版")
private val FANWAI_RE = Regex("""^完结\+(\d+(?:\.\d+)?)番外$""")

private fun hasCjk(s: String?): Boolean {
    if (s.isNullOrEmpty()) return false
    for (c in s) {
        val o = c.code
        if (o in 0x4E00..0x9FFF || o in 0x3400..0x4DBF) return true
    }
    return false
}

private fun progressValue(s: String?): Double? {
    val t = (s ?: "").trim()
    if (t.isEmpty() || hasCjk(t)) return null
    val m = Regex("""^(\d+(?:\.\d+)?)\s*%?$""").matchEntire(t) ?: return null
    return m.groupValues[1].toDoubleOrNull()
}

private fun fanwaiValue(s: String?): Double? {
    val t = (s ?: "").trim()
    if (t.isEmpty()) return null
    val m = FANWAI_RE.matchEntire(t) ?: return null
    return m.groupValues[1].toDoubleOrNull()
}

private fun subKey(author: String, title: String): String =
    "${author.trim().lowercase()}\u0000${title.trim().lowercase()}"

fun selectDuplicateIds(rows: List<DuplicateRow>): List<Long> {
    val subgroups = rows.groupBy { subKey(it.author, it.title) }
    val allResult = mutableSetOf<Long>()

    for ((_, S) in subgroups) {
        if (S.size < 2) continue

        val c = mutableSetOf<Long>()
        val nc = mutableSetOf<Long>()
        val fc = mutableSetOf<Long>()

        val exact = S.groupBy { Triple(it.fileName, it.fileSize, it.progress.trim()) }
        for ((_, g) in exact) {
            if (g.size < 2) continue
            val newest = g.maxWithOrNull(compareBy<DuplicateRow> { it.createdAt }.thenBy { it.id })!!
            nc.add(newest.id)
            for (f in g) if (f.id != newest.id) {
                c.add(f.id); fc.add(f.id)
            }
        }

        val numericFiles = S.filter { progressValue(it.progress) != null }
        val chineseFiles = S.filter { hasCjk(it.progress) }
        val allNumeric = numericFiles.size == S.size

        if (allNumeric) {
            val maxVal = S.maxOf { progressValue(it.progress)!! }
            val maxFiles = S.filter { progressValue(it.progress) == maxVal }
            val maxIds = maxFiles.map { it.id }.toSet()
            maxFiles.forEach { nc.add(it.id) }
            S.forEach { if (it.id !in maxIds) c.add(it.id) }
        } else {
            chineseFiles.forEach { nc.add(it.id) }
            if (chineseFiles.isNotEmpty() && numericFiles.isNotEmpty()) {
                val maxNumVal = numericFiles.maxOf { progressValue(it.progress)!! }
                val maxNumFiles = numericFiles.filter { progressValue(it.progress) == maxNumVal }
                val hasCompletion = S.any { cf -> COMPLETION_KW.any { kw -> (cf.fileName).contains(kw) } }
                val minChineseSize = chineseFiles.minOf { it.fileSize }
                if (hasCompletion && maxNumFiles.all { mn -> mn.fileSize < minChineseSize }) {
                    maxNumFiles.forEach { fc.add(it.id) }
                }
            }
        }

        val maxSize = S.maxOf { it.fileSize }
        val maxSizeCount = S.count { it.fileSize == maxSize }
        if (maxSizeCount == 1) {
            S.forEach { if (it.fileSize == maxSize) nc.add(it.id) }
        }

        val fanwai = S.filter { fanwaiValue(it.progress) != null }
        if (fanwai.isNotEmpty()) {
            val maxN = fanwai.maxOf { fanwaiValue(it.progress)!! }
            val maxNIds = fanwai.filter { fanwaiValue(it.progress) == maxN }.map { it.id }.toSet()
            for (f in fanwai) {
                when {
                    f.id in maxNIds -> { nc.add(f.id); fc.remove(f.id) }
                    f.fileSize == maxSize -> { nc.add(f.id); fc.remove(f.id) }
                    else -> { c.add(f.id); fc.add(f.id) }
                }
            }
        }

        val subResult = (c - nc) + fc
        if (subResult.isNotEmpty()) allResult += subResult
    }
    return allResult.toList().sorted()
}

fun main() {
    var pass = 0
    var fail = 0
    fun check(name: String, actual: Set<Long>, expected: Set<Long>) {
        if (actual == expected) {
            println("[PASS] $name -> $actual")
            pass++
        } else {
            println("[FAIL] $name -> 实际=$actual 期望=$expected")
            fail++
        }
    }

    // 规则 2：纯数字进度，最大者保留，其余勾选
    check(
        "规则2-纯数字进度",
        selectDuplicateIds(
            listOf(
                DuplicateRow(1, "a", 100, "书", "作", "20", "2024-01-01"),
                DuplicateRow(2, "b", 100, "书", "作", "80", "2024-01-02"),
                DuplicateRow(3, "c", 100, "书", "作", "40", "2024-01-03"),
            )
        ).toSet(),
        setOf(1L, 3L)
    )

    // 规则 1：五字段完全相等的精确重复，保留最新
    check(
        "规则1-精确重复保留最新",
        selectDuplicateIds(
            listOf(
                DuplicateRow(10, "same.txt", 500, "书", "作", "50", "2024-01-01"),
                DuplicateRow(11, "same.txt", 500, "书", "作", "50", "2024-01-05"),
                DuplicateRow(12, "same.txt", 500, "书", "作", "50", "2024-01-03"),
            )
        ).toSet(),
        setOf(10L, 12L)
    )

    // 规则 3A：混合组（完结 + 更50），无完结关键词 -> 保守不删
    check(
        "规则3A-混合组保守不删",
        selectDuplicateIds(
            listOf(
                DuplicateRow(20, "x", 100, "书", "作", "完结", "2024-01-01"),
                DuplicateRow(21, "y", 100, "书", "作", "50", "2024-01-02"),
            )
        ).toSet(),
        emptySet()
    )

    // 规则 3B：完结关键词 + 最大数字进度文件更小 -> 强制勾选更50（仅最大数字本）
    check(
        "规则3B-完结特例强制勾选最大数字本",
        selectDuplicateIds(
            listOf(
                DuplicateRow(30, "完结版.txt", 999, "书", "作", "完结", "2024-01-01"),
                DuplicateRow(31, "更50.txt", 50, "书", "作", "50", "2024-01-02"),
                DuplicateRow(32, "更33.txt", 33, "书", "作", "33", "2024-01-03"),
            )
        ).toSet(),
        setOf(31L)
    )

    // 规则 4：唯一最大文件（进度30 大文件）受保护；更小的高进度本被勾选
    check(
        "规则4-唯一最大文件保护",
        selectDuplicateIds(
            listOf(
                DuplicateRow(40, "big.txt", 1000, "书", "作", "30", "2024-01-01"),
                DuplicateRow(41, "s1.txt", 10, "书", "作", "50", "2024-01-02"),
                DuplicateRow(42, "s2.txt", 20, "书", "作", "50", "2024-01-03"),
                DuplicateRow(43, "s3.txt", 30, "书", "作", "40", "2024-01-04"),
            )
        ).toSet(),
        setOf(43L)
    )

    // 规则 5：完结+N番外，数字最大者保留，较小的（文件更小）被勾选
    check(
        "规则5-番外数字最大保留",
        selectDuplicateIds(
            listOf(
                DuplicateRow(50, "f3.txt", 100, "书", "作", "完结+3番外", "2024-01-01"),
                DuplicateRow(51, "f1.txt", 50, "书", "作", "完结+1番外", "2024-01-02"),
            )
        ).toSet(),
        setOf(51L)
    )

    println("\n==== selectDuplicateIds 结果 ($pass pass / $fail fail) ====")
    if (fail > 0) System.exit(1)
}
