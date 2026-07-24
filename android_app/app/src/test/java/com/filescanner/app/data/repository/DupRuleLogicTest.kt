package com.filescanner.app.data.repository

import com.filescanner.app.data.database.entity.DuplicateRow
import com.filescanner.app.data.database.entity.DupRuleConfigEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.regex.Pattern

/**
 * 自定义规则（选处理项 + 写正则）评估逻辑的单元测试。
 * 直接调用真实代码 DupRuleLogic，覆盖：
 *  - 条件 JSON 解析（新格式 field+regex / 旧格式 op+value 兼容 / 空 / 非法）
 *  - 单字段正则命中（文件名/小说名/作者/进度/来源/文件大小/创建日期）
 *  - 非法正则 / 空白正则不抛异常
 *  - 多条条件「且」逻辑
 *  - 命中后动作（check=加入勾选集合 / protect=移除勾选集合）在 selectDuplicateIds 中的应用
 * 说明：内置规则的 enabled 开关在 DAO 层（WHERE enabled=1）过滤，自定义规则的 enabled 同样由
 *       getEnabledUserRules 的 WHERE enabled=1 过滤；本测试聚焦「规则内容」评估逻辑的真实生效。
 */
class DupRuleLogicTest {

    private fun row(
        id: Long = 1,
        fileName: String = "小说_作者_水印.txt",
        title: String = "书名",
        author: String = "张三",
        progress: String = "50",
        source: String = "起点",
        fileSize: Long = 1024,
        createdAt: Long = 1700000000000
    ) = DuplicateRow(id, fileName, title, author, progress, source, fileSize, createdAt)

    private fun rule(conditions: String, action: String = "check") = DupRuleConfigEntity(
        id = 0,
        ruleKey = "u",
        ruleName = "t",
        enabled = true,
        description = "",
        isBuiltin = false,
        conditions = conditions,
        action = action
    )

    // ===================== parseUserConditions =====================

    @Test
    fun parseNewFormat() {
        val list = DupRuleLogic.parseUserConditions("""[{"field":"file_name","regex":"水印"}]""")
        assertEquals(1, list!!.size)
        assertEquals("file_name", list[0]["field"])
        assertEquals("水印", list[0]["regex"])
    }

    @Test
    fun parseOldContains() {
        val list = DupRuleLogic.parseUserConditions("""[{"field":"file_name","op":"contains","value":"水印"}]""")
        assertEquals(Pattern.quote("水印"), list!![0]["regex"])
    }

    @Test
    fun parseOldEq() {
        val list = DupRuleLogic.parseUserConditions("""[{"field":"file_name","op":"eq","value":"水印"}]""")
        assertEquals("^" + Pattern.quote("水印") + "$", list!![0]["regex"])
    }

    @Test
    fun parseOldStartsWith() {
        val list = DupRuleLogic.parseUserConditions("""[{"field":"file_name","op":"starts_with","value":"水印"}]""")
        assertEquals("^" + Pattern.quote("水印"), list!![0]["regex"])
    }

    @Test
    fun parseOldEndsWith() {
        val list = DupRuleLogic.parseUserConditions("""[{"field":"file_name","op":"ends_with","value":"水印"}]""")
        assertEquals(Pattern.quote("水印") + "$", list!![0]["regex"])
    }

    @Test
    fun parseOldNotContains() {
        val list = DupRuleLogic.parseUserConditions("""[{"field":"file_name","op":"not_contains","value":"水印"}]""")
        assertTrue(list!![0]["regex"]!!.contains("(?s)"))
    }

    @Test
    fun parseOldRegex() {
        val list = DupRuleLogic.parseUserConditions("""[{"field":"file_name","op":"regex","value":"^水.印$"}]""")
        assertEquals("^水.印$", list!![0]["regex"])
    }

    @Test
    fun parseEmpty() {
        assertEquals(0, DupRuleLogic.parseUserConditions("")!!.size)
        assertEquals(0, DupRuleLogic.parseUserConditions("[]")!!.size)
    }

    @Test
    fun parseInvalidJsonReturnsNull() {
        assertNull(DupRuleLogic.parseUserConditions("{not json"))
    }

    @Test
    fun parseSkipsBlankField() {
        val list = DupRuleLogic.parseUserConditions("""[{"field":"","regex":"x"},{"field":"file_name","regex":"y"}]""")
        assertEquals(1, list!!.size)
        assertEquals("file_name", list[0]["field"])
    }

    // ===================== oldOpToRegex =====================

    @Test
    fun oldOpToRegexUnit() {
        assertEquals(Pattern.quote("水印"), DupRuleLogic.oldOpToRegex("contains", "水印"))
        assertEquals("^" + Pattern.quote("水印") + "$", DupRuleLogic.oldOpToRegex("eq", "水印"))
        assertEquals("^" + Pattern.quote("水印"), DupRuleLogic.oldOpToRegex("starts_with", "水印"))
        assertEquals(Pattern.quote("水印") + "$", DupRuleLogic.oldOpToRegex("ends_with", "水印"))
        assertEquals("", DupRuleLogic.oldOpToRegex("unknown_op", "水印")) // else 分支转不出
        assertEquals("", DupRuleLogic.oldOpToRegex("contains", ""))      // 空值转不出
    }

    // ===================== evalSingleCondition 各字段 =====================

    @Test
    fun evalFileNameHitAndMiss() {
        assertTrue(DupRuleLogic.evalSingleCondition(row(), mapOf("field" to "file_name", "regex" to "水印")))
        assertFalse(DupRuleLogic.evalSingleCondition(row(), mapOf("field" to "file_name", "regex" to "不存在")))
    }

    @Test
    fun evalNovelName() {
        assertTrue(DupRuleLogic.evalSingleCondition(row(title = "斗破苍穹"), mapOf("field" to "novel_name", "regex" to "斗破")))
        assertFalse(DupRuleLogic.evalSingleCondition(row(title = "斗破"), mapOf("field" to "novel_name", "regex" to "苍穹")))
    }

    @Test
    fun evalAuthorExact() {
        assertTrue(DupRuleLogic.evalSingleCondition(row(author = "张三"), mapOf("field" to "author", "regex" to "^张三$")))
        assertFalse(DupRuleLogic.evalSingleCondition(row(author = "张三丰"), mapOf("field" to "author", "regex" to "^张三$")))
    }

    @Test
    fun evalProgress() {
        assertTrue(DupRuleLogic.evalSingleCondition(row(progress = "50"), mapOf("field" to "progress", "regex" to "\\d+")))
    }

    @Test
    fun evalSource() {
        assertTrue(DupRuleLogic.evalSingleCondition(row(source = "起点"), mapOf("field" to "source", "regex" to "起点")))
    }

    @Test
    fun evalFileSize() {
        assertTrue(DupRuleLogic.evalSingleCondition(row(fileSize = 1024), mapOf("field" to "file_size", "regex" to "1024")))
    }

    @Test
    fun evalCreatedDate() {
        assertTrue(DupRuleLogic.evalSingleCondition(row(createdAt = 1700000000000), mapOf("field" to "created_date", "regex" to "1700")))
    }

    @Test
    fun evalInvalidRegexNoThrow() {
        assertFalse(DupRuleLogic.evalSingleCondition(row(), mapOf("field" to "file_name", "regex" to "(")))
    }

    @Test
    fun evalBlankRegex() {
        assertFalse(DupRuleLogic.evalSingleCondition(row(), mapOf("field" to "file_name", "regex" to "")))
    }

    @Test
    fun evalUnknownFieldReturnsTrue() {
        // 未知字段视为「命中」（兼容未知处理项）
        assertTrue(DupRuleLogic.evalSingleCondition(row(), mapOf("field" to "whatever", "regex" to "x")))
    }

    // ===================== evaluateUserRule =====================

    @Test
    fun userRuleCheckHit() {
        assertTrue(DupRuleLogic.evaluateUserRule(row(), rule("""[{"field":"file_name","regex":"水印"}]""", "check")))
    }

    @Test
    fun userRuleProtectHit() {
        // 命中即返回 true；动作(check/protect)由调用方区分
        assertTrue(DupRuleLogic.evaluateUserRule(row(), rule("""[{"field":"file_name","regex":"水印"}]""", "protect")))
    }

    @Test
    fun userRuleMiss() {
        assertFalse(DupRuleLogic.evaluateUserRule(row(), rule("""[{"field":"file_name","regex":"不存在"}]""", "check")))
    }

    @Test
    fun userRuleEmptyConditions() {
        assertFalse(DupRuleLogic.evaluateUserRule(row(), rule("[]", "check")))
    }

    @Test
    fun userRuleNullConditions() {
        val r = DupRuleConfigEntity(id = 0, ruleKey = "u", ruleName = "t", enabled = true, description = "", isBuiltin = false, conditions = null, action = "check")
        assertFalse(DupRuleLogic.evaluateUserRule(row(), r))
    }

    @Test
    fun userRuleMultiAndAllMatch() {
        val r = rule("""[{"field":"file_name","regex":"水印"},{"field":"author","regex":"张三"}]""", "check")
        assertTrue(DupRuleLogic.evaluateUserRule(row(), r))
    }

    @Test
    fun userRuleMultiAndPartialMiss() {
        val r = rule("""[{"field":"file_name","regex":"水印"},{"field":"author","regex":"李四"}]""", "check")
        assertFalse(DupRuleLogic.evaluateUserRule(row(), r))
    }

    // ===================== 自定义规则在「勾选重复」中的最终生效（复刻 selectDuplicateIds 的自定义规则段） =====================

    @Test
    fun applyUserRuleCheckAddsOnlyMatched() {
        val rows = listOf(
            row(id = 1, fileName = "a_水印.txt"),
            row(id = 2, fileName = "b_normal.txt"),
        )
        val r = rule("""[{"field":"file_name","regex":"水印"}]""", "check")
        val result = mutableSetOf<Long>()
        for (row in rows) {
            if (DupRuleLogic.evaluateUserRule(row, r)) {
                if ((r.action ?: "check") == "check") result.add(row.id) else result.remove(row.id)
            }
        }
        assertEquals(setOf(1L), result) // 只有含「水印」的文件被勾选
    }

    @Test
    fun applyUserRuleProtectRemovesMatched() {
        val rows = listOf(
            row(id = 1, fileName = "a_水印.txt"),
            row(id = 2, fileName = "b_水印.txt"),
        )
        val r = rule("""[{"field":"file_name","regex":"水印"}]""", "protect")
        val result = mutableSetOf<Long>(1L, 2L) // 假设已被内置规则勾选
        for (row in rows) {
            if (DupRuleLogic.evaluateUserRule(row, r)) {
                if ((r.action ?: "check") == "check") result.add(row.id) else result.remove(row.id)
            }
        }
        assertTrue(result.isEmpty()) // 保护动作移除所有匹配项
    }

    @Test
    fun applyUserRuleProtectKeepsUnmatched() {
        val rows = listOf(
            row(id = 1, fileName = "a_水印.txt"),
            row(id = 2, fileName = "b_normal.txt"),
        )
        val r = rule("""[{"field":"file_name","regex":"水印"}]""", "protect")
        val result = mutableSetOf<Long>(1L, 2L)
        for (row in rows) {
            if (DupRuleLogic.evaluateUserRule(row, r)) {
                if ((r.action ?: "check") == "check") result.add(row.id) else result.remove(row.id)
            }
        }
        assertEquals(setOf(2L), result) // 未匹配的文件仍被勾选
    }
}
