package com.filescanner.app.util

import com.filescanner.app.data.database.entity.KeywordReplaceRuleEntity

/**
 * 关键词替换工具（对齐 PC 端 backend/keyword_replace.py）。
 *
 * applyRules：按规则顺序对文本依次执行“精确字符串替换”，
 * pattern 命中即整段替换为 replacement（空串=删除）。
 * PC 用 str.replace（区分大小写、替换全部），Kotlin 的 String.replace 行为一致。
 */
object KeywordReplace {
    /** 作用域常量，与 PC 端 scope 字段保持一致。 */
    const val SCOPE_SCAN = "scan"   // 扫描阶段：作用于文件名
    const val SCOPE_PARSE = "parse" // 解析阶段：作用于 书名/作者/进度/来源

    fun applyRules(text: String?, rules: List<KeywordReplaceRuleEntity>): String? {
        if (text.isNullOrEmpty() || rules.isEmpty()) return text
        var result: String = text
        for (r in rules) {
            val p = r.pattern
            if (p.isNotEmpty()) {
                result = result.replace(p, r.replacement)
            }
        }
        return result
    }

    /**
     * 预置的默认关键词替换规则（作用域=扫描阶段，作用于文件名）。
     * 用于去除网文 txt 文件名上常见的平台水印/标记（如 [草2莓]、[草 莓]、【lili】 等），
     * 减少用户手动配置工作量。仅在规则表为空时由 FileScannerApp 启动时写入一次，
     * 之后用户可在设置里正常查看 / 新增 / 编辑 / 删除 / 启用禁用。
     */
    val DEFAULT_KEYWORD_RULES: List<KeywordReplaceRuleEntity> = listOf(
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "[草2莓]", replacement = "", sortOrder = 1),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【草2莓", replacement = "", sortOrder = 2),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【草2莓】", replacement = "", sortOrder = 3),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "[草 莓]", replacement = "", sortOrder = 4),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "[草 莓", replacement = "", sortOrder = 5),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【lili】", replacement = "", sortOrder = 6),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "（l.i.）", replacement = "", sortOrder = 7),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "(l.i.）", replacement = "", sortOrder = 8),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "（l.i.)", replacement = "", sortOrder = 9),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "(l.i.)", replacement = "", sortOrder = 10),
        // —— 以下为 caomei / 3167 937770 水印系列及扩展名修正（与 PC/鸿蒙端同步）——
        // 顺序约定：① 含「の企鹅3167 937770」的完整变体须先于裸「の企鹅3167 937770」；
        // ② 成对括号变体须先于只去开头括号的变体，避免残留孤立前缀/括号。
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "..txt", replacement = ".txt", sortOrder = 11),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【草莓】", replacement = "", sortOrder = 12),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【草 莓", replacement = "", sortOrder = 13),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【＋V信kxee6699】", replacement = "", sortOrder = 14),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = ".3167 937770", replacement = "", sortOrder = 15),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【颜3167 937770", replacement = "", sortOrder = 16),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【Q主caomeiの企鹅3167 937770】", replacement = "", sortOrder = 17),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【Q主caomei】", replacement = "", sortOrder = 18),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "_caomeiの企鹅3167 937770_", replacement = "", sortOrder = 19),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "（caomeiの企鹅3167 937770", replacement = "", sortOrder = 20),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "(caomeiの企鹅3167 937770", replacement = "", sortOrder = 21),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【qzcaomeiの企鹅3167 937770", replacement = "", sortOrder = 22),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = ".QZcaomeiの企鹅3167 937770", replacement = "", sortOrder = 23),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "_caomeiの企鹅3167 937770", replacement = "", sortOrder = 24),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = ".caomeiの企鹅3167 937770", replacement = "", sortOrder = 25),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "の企鹅3167 937770", replacement = "", sortOrder = 26),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "[3167 937770]", replacement = "", sortOrder = 27),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "[3167 937770", replacement = "", sortOrder = 28),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "3167937770", replacement = "", sortOrder = 29),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "_3167 937770", replacement = "", sortOrder = 30),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "（颜3167 937770", replacement = "", sortOrder = 31),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【3167 937770]", replacement = "", sortOrder = 32),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "_.txt", replacement = ".txt", sortOrder = 33),
        // —— 2026-07-24 新增 7 条默认替换规则（与 PC/鸿蒙端同步）——
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【昭昭明月BG】", replacement = "", sortOrder = 34),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【昭昭明月BL】", replacement = "", sortOrder = 35),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【推荐】", replacement = "", sortOrder = 36),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【全本校对】", replacement = "", sortOrder = 37),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【全本精校】", replacement = "", sortOrder = 38),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【BL】", replacement = "", sortOrder = 39),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【BG】", replacement = "", sortOrder = 40),
        // —— 新增默认替换规则 ——
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【YLW】", replacement = "", sortOrder = 41),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "『推』", replacement = "", sortOrder = 42),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【YLW连载】", replacement = "", sortOrder = 43),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【棠】", replacement = "", sortOrder = 44),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【公众号：推文日记】", replacement = "", sortOrder = 45),
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "【书香门第★九落】", replacement = "", sortOrder = 46)
    )
}
