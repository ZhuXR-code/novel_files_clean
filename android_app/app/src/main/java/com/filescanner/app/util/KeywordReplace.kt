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
        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = "(l.i.)", replacement = "", sortOrder = 10)
    )
}
