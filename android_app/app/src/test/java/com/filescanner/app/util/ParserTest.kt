package com.filescanner.app.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 文件名解析单测（纯 JVM，无 Android 依赖）。
 * 覆盖：基础书名/作者提取、关键词屏蔽、圆括号(全角/半角)进度与状态提取、
 * 来源提取、多括号清洗。与 PC 端 backend.regex_parser._extract_source_progress 对齐。
 */
class ParserTest {

    private fun parse(fname: String) = Parser.parseFileName(fname)

    // ---------------- 基础书名 / 作者 ----------------
    @Test
    fun `标准书名+作者 含圆括号进度`() {
        val r = parse("《都市奇缘》作者：张三（更50）.txt")
        assertEquals("都市奇缘", r.title)
        assertEquals("张三", r.author)
    }

    @Test
    fun `无作者 仅书名`() {
        val r = parse("《深海》123.txt")
        assertEquals("深海", r.title)
        assertEquals("", r.author)
    }

    @Test
    fun `开头来源角标 书名+作者`() {
        val r = parse("【晋江】《名》作者：王五.txt")
        assertEquals("名", r.title)
        assertEquals("王五", r.author)
        assertTrue(r.source.contains("晋江"))
    }

    @Test
    fun `作者无书名顺序反转`() {
        // 作者在前《书名》在后的格式：Parser 用《》兜底提取书名，忽略前置作者（与 PC 端一致的限制）
        val r = parse("作者：李四《书名》.txt")
        assertEquals("书名", r.title)
        assertEquals("", r.author)
    }

    // ---------------- 关键词 / 纯数字屏蔽 ----------------
    @Test
    fun `说明 关键词屏蔽`() {
        assertEquals("", parse("说明.txt").title)
    }

    @Test
    fun `README 屏蔽`() {
        assertEquals("", parse("README.txt").title)
    }

    @Test
    fun `纯数字文件名 屏蔽`() {
        assertEquals("", parse("12345.txt").title)
    }

    @Test
    fun `无作者无书名 普通空格格式`() {
        // 纯空格分隔且无“作者”/“by”关键词：Parser 兜底把整段当作书名（与 PC 端一致的限制）
        val r = parse("仙侠世界 李四 更100.txt")
        assertEquals("仙侠世界 李四 更100", r.title)
        assertEquals("", r.author)
    }

    @Test
    fun `题材前缀仙侠被剥离 书名余下部分`() {
        // RE_CATEGORY：题材词后跟分隔符时，题材前缀从书名中剥离（预期行为，回归锁定）
        assertEquals("世界", parse("仙侠世界 - 李四 - 更100.txt").title)
    }

    @Test
    fun `无括号 书名+作者`() {
        val r = parse("《全职高手》作者：蝴蝶蓝.txt")
        assertEquals("全职高手", r.title)
        assertEquals("蝴蝶蓝", r.author)
    }

    @Test
    fun `无作者 仅书名括号`() {
        assertEquals("无作者", parse("《无作者》.txt").title)
    }

    @Test
    fun `番外合集 书名`() {
        assertEquals("天官赐福", parse("《天官赐福》作者：墨香铜臭 番外合集.txt").title)
    }

    @Test
    fun `无书名号 书名+作者+进度`() {
        // 纯空格分隔且无关键词：兜底整段作书名（已知限制，与 PC 端一致）
        val r = parse("诡秘之主 爱潜水的乌贼 更1500.txt")
        assertEquals("诡秘之主 爱潜水的乌贼 更1500", r.title)
        assertEquals("", r.author)
    }

    // ---------------- 修复验证：圆括号进度/状态（对齐 PC） ----------------
    @Test
    fun `全角圆括号 更50 进度=50`() {
        assertEquals("50", parse("《都市奇缘》作者：张三（更50）.txt").progress)
    }

    @Test
    fun `全角圆括号 更300 进度=300 来源保持纵横`() {
        val r = parse("《庆余年》作者：猫腻【纵横】（更300）.txt")
        assertEquals("300", r.progress)
        assertEquals("纵横", r.source)
    }

    @Test
    fun `全角圆括号 完结 状态=完结`() {
        assertEquals("完结", parse("[废文]《默读》作者：priest（完结）.txt").progress)
    }

    @Test
    fun `半角圆括号 更200 进度=200 来源保持起点`() {
        val r = parse("《诛仙》作者：萧鼎 [起点] (更200).txt")
        assertEquals("200", r.progress)
        assertEquals("起点", r.source)
    }

    @Test
    fun `更50 精校 后缀 进度=50 作者清洗 更50`() {
        val r = parse("《都市奇缘》作者：张三（更50）精校.txt")
        assertEquals("50", r.progress)
        assertEquals("张三", r.author)
    }

    @Test
    fun `废文完结 作者含修同人后缀 书名作者进度来源全正确`() {
        // [废文 完结]《危险关系》作者：Nnnr（【修】山海镜花 融共同人）.txt
        // 期望：书名=危险关系 / 作者=Nnnr / 进度=完结 / 来源=废文
        val r = parse("[废文 完结]《危险关系》作者：Nnnr（【修】山海镜花 融共同人）.txt")
        assertEquals("危险关系", r.title)
        assertEquals("Nnnr", r.author)
        assertEquals("完结", r.progress)
        assertEquals("废文", r.source)
    }

    @Test
    fun `双括号 起点+更200 来源=起点 进度=200`() {
        val r = parse("《诛仙》作者：萧鼎（起点）（更200）.txt")
        assertEquals("起点", r.source)
        assertEquals("200", r.progress)
    }

    @Test
    fun `方括号来源 圆括号完结 来源=起点 状态=完结`() {
        val r = parse("《诛仙》作者：萧鼎 [起点]（完结）.txt")
        assertEquals("起点", r.source)
        assertEquals("完结", r.progress)
    }
}
