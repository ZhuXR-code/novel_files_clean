package com.filescanner.app.data.repository

import com.filescanner.app.data.database.entity.DuplicateRow
import com.filescanner.app.data.database.entity.DupRuleConfigEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 重复规则端到端生效测试（纯 JVM，无需 Android/Room）。
 *
 * 直接调用 FileRepository.selectDuplicateIds 共用的核心纯函数 DupRuleLogic.computeDuplicateChecks。
 * 调用方传入的 enabledBuiltinKeys / userRules 正是 selectDuplicateIds 从 DAO 取到的
 * （内置：getEnabledBuiltinRuleKeys() 内部 SQL `WHERE enabled = 1 AND is_builtin = 1`；
 *  自定义：getEnabledUserRules() 内部 SQL `WHERE enabled = 1 AND is_builtin = 0 AND conditions IS NOT NULL`）。
 * 因此「只传入被勾选的规则」就等价于「勾选才生效、不勾选不生效」，可在此真实验证。
 *
 * 覆盖：每条内置规则 key 勾选/取消对结果的影响，以及自定义规则 action=check / action=protect 的启用与停用。
 */
class DupRuleIntegrationTest {

    private val ALL_BUILTIN = setOf("rule1", "rule2", "rule3a", "rule3b", "rule4", "rule5")

    private fun row(
        id: Long, fileName: String, title: String, author: String,
        progress: String, size: Long, createdAt: Long, source: String = ""
    ) = DuplicateRow(
        id = id, fileName = fileName, title = title, author = author,
        progress = progress, source = source, fileSize = size, createdAt = createdAt
    )

    private fun check(rows: List<DuplicateRow>, builtin: Set<String>, userRules: List<DupRuleConfigEntity> = emptyList()): Set<Long> {
        return DupRuleLogic.computeDuplicateChecks(rows, builtin, userRules).first
    }

    private fun customRule(key: String, regex: String, action: String) = DupRuleConfigEntity(
        ruleKey = key, ruleName = key, enabled = true, isBuiltin = false,
        conditions = "[{\"field\":\"file_name\",\"regex\":\"$regex\"}]", action = action, sortOrder = 9
    )

    // ===================== 内置规则：勾选才生效 =====================

    @Test
    fun rule1_enabled_checksOlderExactDup() {
        val rows = listOf(
            row(1L, "A.txt", "书名", "作者", "10", 100L, 100L),
            row(2L, "B.txt", "书名", "作者", "10", 100L, 200L), // 更新 -> 不勾选
        )
        assertEquals(setOf(1L), check(rows, setOf("rule1")))
    }

    @Test
    fun rule1_disabled_noCheck() {
        val rows = listOf(
            row(1L, "A.txt", "书名", "作者", "10", 100L, 100L),
            row(2L, "B.txt", "书名", "作者", "10", 100L, 200L),
        )
        assertTrue(check(rows, emptySet()).isEmpty())
    }

    @Test
    fun rule2_enabled_checksLowerProgress() {
        val rows = listOf(
            row(1L, "A.txt", "书名", "作者", "5", 100L, 100L),
            row(2L, "B.txt", "书名", "作者", "5", 100L, 200L),
            row(3L, "C.txt", "书名", "作者", "10", 100L, 300L), // 最大进度 -> 不勾选
        )
        assertEquals(setOf(1L, 2L), check(rows, setOf("rule2")))
    }

    @Test
    fun rule2_disabled_noCheck() {
        val rows = listOf(
            row(1L, "A.txt", "书名", "作者", "5", 100L, 100L),
            row(3L, "C.txt", "书名", "作者", "10", 100L, 300L),
        )
        assertTrue(check(rows, emptySet()).isEmpty())
    }

    @Test
    fun rule4_enabled_protectsMaxSizeAgainstRule2() {
        // rule2 单独会把进度较低的 id1、id2 都勾选；rule4 启用后保护唯一最大文件 id2
        val rows = listOf(
            row(1L, "A.txt", "书名", "作者", "5", 100L, 100L),
            row(2L, "B.txt", "书名", "作者", "5", 200L, 200L), // 唯一最大 -> rule4 保护
            row(3L, "C.txt", "书名", "作者", "10", 50L, 300L),
        )
        assertEquals(setOf(1L, 2L), check(rows, setOf("rule2")))            // rule4 关闭
        assertEquals(setOf(1L), check(rows, setOf("rule2", "rule4")))       // rule4 启用：id2 不再勾选
    }

    @Test
    fun rule5_enabled_protectsMaxFanwai() {
        val rows = listOf(
            row(1L, "A.txt", "书名", "作者", "完结+1番外", 100L, 100L),
            row(2L, "B.txt", "书名", "作者", "完结+2番外", 100L, 200L),
            row(3L, "C.txt", "书名", "作者", "完结+3番外", 100L, 300L), // 最大 N -> 不勾选
        )
        assertTrue(check(rows, emptySet()).isEmpty())                      // rule5 关闭
        assertEquals(setOf(1L, 2L), check(rows, setOf("rule5")))           // rule5 启用：仅最大 N 不勾选
    }

    @Test
    fun rule3b_enabled_forcesCheckMaxNumericWhenCompletion() {
        // 存在「完本」大文件(A) + 数字进度最大但体积更小的文件(B)时，rule3b 强制勾选 B
        val rows = listOf(
            row(1L, "完本大作.txt", "书名", "作者", "更新至100", 200L, 100L), // 完结字样 + 体积大（A）
            row(2L, "B.txt", "书名", "作者", "100", 50L, 200L),  // 数字进度最大 + 体积小（B）
            row(3L, "C.txt", "书名", "作者", "50", 30L, 300L),   // 数字进度较小
        )
        assertEquals(setOf(3L), check(rows, setOf("rule2")))               // rule3b 关闭：rule2 只勾选较低进度 id3
        assertEquals(setOf(2L, 3L), check(rows, setOf("rule2", "rule3b"))) // rule3b 启用：id2(进度最大但比完结版小)也强制勾选
    }

    @Test
    fun rule3a_enabled_protectsChineseProgress() {
        // rule3a 启用：中文进度文件被保护（从强制勾选集合移除），即便 rule1 会勾选较旧者
        val rows = listOf(
            row(1L, "A.txt", "书名", "作者", "更新至50", 100L, 100L), // 较旧 -> 原会被 rule1 勾选
            row(2L, "B.txt", "书名", "作者", "更新至50", 100L, 200L),
        )
        assertTrue(check(rows, setOf("rule1", "rule3a")).isEmpty())   // rule3a 保护生效
        assertEquals(setOf(1L), check(rows, setOf("rule1")))          // 无 rule3a：rule1 勾选较旧者
    }

    // ===================== 自定义规则：check / protect =====================

    @Test
    fun customCheck_enabled_checksMatched() {
        val rows = listOf(
            row(1L, "正文.txt", "书名", "作者", "10", 100L, 100L),
            row(3L, "水印版本.txt", "书名", "作者", "10", 100L, 200L), // 被自定义规则命中
        )
        val rule = customRule("u_wm", "水印", "check")
        assertTrue(check(rows, emptySet()).isEmpty())                     // 无内置规则
        assertEquals(setOf(3L), check(rows, emptySet(), listOf(rule)))    // 自定义 check 启用：命中勾选
    }

    @Test
    fun customCheck_disabled_noCheck() {
        val rows = listOf(
            row(1L, "正文.txt", "书名", "作者", "10", 100L, 100L),
            row(3L, "水印版本.txt", "书名", "作者", "10", 100L, 200L),
        )
        // 自定义规则停用 == DAO 不返回该规则（不传入 computeDuplicateChecks）
        assertTrue(check(rows, emptySet(), emptyList()).isEmpty())
    }

    @Test
    fun customProtect_enabled_removesFromChecked() {
        // rule1 会勾选较旧文件 id1；自定义 protect 命中 id1 -> 移除
        val rows = listOf(
            row(1L, "正文独享.txt", "书名", "作者", "10", 100L, 100L),
            row(2L, "其他.txt", "书名", "作者", "10", 100L, 200L),
        )
        val protect = customRule("u_protect", "独享", "protect")
        assertEquals(setOf(1L), check(rows, setOf("rule1")))              // 无 protect：id1 勾选
        assertTrue(check(rows, setOf("rule1"), listOf(protect)).isEmpty()) // 有 protect：id1 被移除
    }

    // ===================== 组合：全部内置规则启用 =====================

    @Test
    fun allBuiltinEnabled_combinedResult() {
        val rows = listOf(
            row(1L, "A.txt", "书名", "作者", "10", 100L, 100L),
            row(2L, "B.txt", "书名", "作者", "10", 100L, 200L), // 较新 -> 不勾选(rule1)
            row(3L, "水印.txt", "书名", "作者", "5", 100L, 300L), // 进度较低被 rule2 勾选（与另外两本同大小，避免 rule4 干扰）
        )
        val result = check(rows, ALL_BUILTIN)
        assertTrue(result.contains(1L)) // 较旧精确重复
        assertTrue(result.contains(3L)) // 较低进度
        assertFalse(result.contains(2L)) // 较新 / 最大进度
    }
}
