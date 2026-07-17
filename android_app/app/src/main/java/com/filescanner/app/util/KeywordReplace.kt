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
}
