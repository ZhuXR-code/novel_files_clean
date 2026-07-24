package com.filescanner.app.data.repository

import com.filescanner.app.data.database.entity.DuplicateRow
import com.filescanner.app.data.database.entity.DupRuleConfigEntity
import org.json.JSONArray

/**
 * 自定义规则评估的纯逻辑（不依赖 Android / Room），便于单元测试直接调用。
 * FileRepository.selectDuplicateIds 委托本对象应用用户自定义规则。
 */
internal object DupRuleLogic {

    /**
     * 评估一条用户自定义规则是否命中该行。
     * @param row 行数据
     * @param rule 用户自定义规则实体，含 conditions JSON + action
     * @return 所有条件同时满足（且）则返回 true
     */
    fun evaluateUserRule(row: DuplicateRow, rule: DupRuleConfigEntity): Boolean {
        val conditionsJson = rule.conditions ?: return false
        val conditions = parseUserConditions(conditionsJson) ?: return false
        if (conditions.isEmpty()) return false
        // 所有条件同时满足才算命中
        for (cond in conditions) {
            if (!evalSingleCondition(row, cond)) return false
        }
        return true
    }

    /**
     * 解析用户自定义条件的 JSON 字符串。
     * 新格式: [{"field":"file_name","regex":"水印"}, ...]（直接正则匹配）。
     * 兼容旧格式: [{"field":"file_name","op":"contains","value":"水印"}, ...]，会尽量转正则。
     * 返回 null 表示规则无法解析（视为「全部命中」，交由后续动作决定）。
     */
    fun parseUserConditions(json: String): List<Map<String, String>>? {
        if (json.isBlank() || json == "[]") return emptyList()
        return try {
            val arr = JSONArray(json)
            val items = mutableListOf<Map<String, String>>()
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val field = obj.optString("field", "")
                if (field.isBlank()) continue
                val regex = if (obj.has("regex")) {
                    obj.optString("regex", "")
                } else {
                    oldOpToRegex(obj.optString("op", "eq"), obj.optString("value", ""))
                }
                items.add(mapOf("field" to field, "regex" to regex))
            }
            items
        } catch (_: Exception) { null }
    }

    /** 把旧格式 op+value 尽量转成正则，兼容已有自定义规则。转换不出返回空串。 */
    fun oldOpToRegex(op: String, value: String): String {
        if (value.isBlank()) return ""
        val esc = Regex.escape(value)
        return when (op) {
            "contains" -> esc
            "not_contains" -> "(?s)^(?:(?!$esc).)*$"
            "starts_with" -> "^$esc"
            "ends_with" -> "$esc$"
            "eq" -> "^$esc$"
            "neq" -> "(?s)^(?:(?!$esc).)*$"
            "regex" -> value
            else -> ""
        }
    }

    /** 评估单条条件：对所选字段用正则匹配。 */
    fun evalSingleCondition(row: DuplicateRow, cond: Map<String, String>): Boolean {
        val field = cond["field"] ?: return true
        val pattern = cond["regex"] ?: return false
        if (pattern.isBlank()) return false

        // 获取实际值
        val actual = when (field) {
            "file_name" -> row.fileName
            "novel_name" -> row.title
            "author" -> row.author
            "progress" -> row.progress
            "source" -> row.source
            "file_size" -> row.fileSize.toString()
            "created_date" -> row.createdAt.toString()
            else -> return true
        } ?: ""

        return try {
            Regex(pattern).containsMatchIn(actual)
        } catch (_: Exception) { false }
    }

    // ===================== 内置规则（五则）评估所需的纯工具 =====================

    /** 文件名中代表"已完结/完整版"的关键词：用于规则 3 的特例判定。 */
    private val COMPLETION_KW = listOf("完结", "完本", "全本", "全集", "完整", "全套", "全集版")

    /** 进度【严格】匹配「完结+数字番外」或「完结+番外数字」正则（用于规则 5）。 */
    private val FANWAI_RE = Regex("""^完结\+(?:(\d+(?:\.\d+)?)番外|番外(\d+(?:\.\d+)?))$""")

    /** 判断字符串是否含有中文（CJK）字符。 */
    private fun hasCjk(s: String?): Boolean {
        if (s.isNullOrEmpty()) return false
        for (c in s) {
            val o = c.code
            if (o in 0x4E00..0x9FFF || o in 0x3400..0x4DBF) return true
        }
        return false
    }

    /** 若进度为纯数字（可选小数、可选尾随 %），返回 Double 数值，否则返回 null。 */
    private fun progressValue(s: String?): Double? {
        val t = (s ?: "").trim()
        if (t.isEmpty() || hasCjk(t)) return null
        val m = Regex("""^(\d+(?:\.\d+)?)\s*%?$""").matchEntire(t) ?: return null
        return m.groupValues[1].toDoubleOrNull()
    }

    /** 若进度匹配「完结+N番外」或「完结+番外N」，返回数字 N，否则 null。 */
    private fun fanwaiValue(s: String?): Double? {
        val t = (s ?: "").trim()
        if (t.isEmpty()) return null
        val m = FANWAI_RE.matchEntire(t) ?: return null
        val n = m.groupValues[1].ifEmpty { m.groupValues[2] }
        return n.toDoubleOrNull()
    }

    /** (作者 + 书名) 归一化子分组键（统一小写、去空格）。 */
    private fun subKey(author: String, title: String): String =
        "${author.trim().lowercase()}\u0000${title.trim().lowercase()}"

    /**
     * 计算「应勾选重复文件」的集合（纯函数，不读写数据库，便于单元测试）。
     *
     * 与 FileRepository.selectDuplicateIds 的计算体完全一致；区别仅在于：
     *  - 内置规则的生效集合由调用方传入 [enabledBuiltinKeys]（对应 getEnabledBuiltinRuleKeys()，
     *    其内部 SQL 为 `WHERE enabled = 1 AND is_builtin = 1`）；
     *  - 自定义规则由调用方传入 [userRules]（对应 getEnabledUserRules()，
     *    其内部 SQL 为 `WHERE enabled = 1 AND is_builtin = 0 AND conditions IS NOT NULL`）。
     * 因此：只有被传入（即被勾选/启用）的规则会参与计算 —— 直接体现「勾选才生效、不勾选不生效」。
     *
     * @return Pair(应勾选的 id 集合, 各重复子组的说明行列表)
     */
    fun computeDuplicateChecks(
        rows: List<DuplicateRow>,
        enabledBuiltinKeys: Set<String>,
        userRules: List<DupRuleConfigEntity>
    ): Pair<Set<Long>, List<String>> {
        val subgroups = rows.groupBy { subKey(it.author, it.title) }
        val allResult = mutableSetOf<Long>()
        val detailLines = mutableListOf<String>()

        for ((_, S) in subgroups) {
            if (S.size < 2) continue

            val c = mutableSetOf<Long>()   // 应勾选
            val nc = mutableSetOf<Long>()  // 永不勾选（保护）
            val fc = mutableSetOf<Long>()  // 强制勾选（覆盖保护）

            // ── 规则 1：完全相等去重 ──
            if ("rule1" in enabledBuiltinKeys) {
                val exact = S.groupBy { it.fileSize to it.progress.trim() }
                for ((_, g) in exact) {
                    if (g.size < 2) continue
                    val newest = g.maxWithOrNull(compareBy<DuplicateRow> { it.createdAt }.thenBy { it.id })!!
                    nc.add(newest.id)
                    for (f in g) if (f.id != newest.id) {
                        c.add(f.id)
                        fc.add(f.id)
                    }
                }
            }

            val numericFiles = S.filter { progressValue(it.progress) != null }
            val chineseFiles = S.filter { hasCjk(it.progress) }

            // ── 规则 2：纯数字进度对比 ──
            if ("rule2" in enabledBuiltinKeys) {
                if (numericFiles.size >= 2) {
                    val maxVal = numericFiles.maxOf { progressValue(it.progress)!! }
                    val maxFiles = numericFiles.filter { progressValue(it.progress) == maxVal }
                    maxFiles.forEach { nc.add(it.id) }
                    for (f in numericFiles) {
                        if (progressValue(f.progress) != maxVal) {
                            c.add(f.id)
                            fc.add(f.id)
                        }
                    }
                }
            }

            // ── 规则 3A：含中文进度保护 ──
            if ("rule3a" in enabledBuiltinKeys) {
                chineseFiles.forEach { nc.add(it.id); fc.remove(it.id) }
            }

            // ── 规则 3B：完结特例 ──
            // 组内存在「文件名含完结/全本等字样」的文件时，若纯数字进度最大的文件
            // 其体积比这些「完结字样文件」中最小的还要小，说明它是残缺版，强制勾选删除。
            if ("rule3b" in enabledBuiltinKeys) {
                if (numericFiles.isNotEmpty()) {
                    val maxNumVal = numericFiles.maxOf { progressValue(it.progress)!! }
                    val maxNumFiles = numericFiles.filter { progressValue(it.progress) == maxNumVal }
                    val completionFiles = S.filter { f -> COMPLETION_KW.any { kw -> f.fileName.contains(kw) } }
                    if (completionFiles.isNotEmpty()) {
                        val minCompletionSize = completionFiles.minOf { it.fileSize }
                        if (maxNumFiles.all { mn -> mn.fileSize < minCompletionSize }) {
                            maxNumFiles.forEach { fc.add(it.id) }
                        }
                    }
                }
            }

            val maxSize = S.maxOf { it.fileSize }
            val maxSizeCount = S.count { it.fileSize == maxSize }

            // ── 规则 4：最大文件不勾选 ──
            if ("rule4" in enabledBuiltinKeys) {
                if (maxSizeCount == 1) {
                    S.forEach { if (it.fileSize == maxSize) { nc.add(it.id); fc.remove(it.id) } }
                }
            }

            // ── 规则 5：完结+N番外/完结+番外N去重 ──
            if ("rule5" in enabledBuiltinKeys) {
                val fanwai = S.filter { fanwaiValue(it.progress) != null }
                if (fanwai.isNotEmpty()) {
                    val maxN = fanwai.maxOf { fanwaiValue(it.progress)!! }
                    val maxNIds = fanwai.filter { fanwaiValue(it.progress) == maxN }.map { it.id }.toSet()
                    for (f in fanwai) {
                        when {
                            f.id in maxNIds -> { nc.add(f.id); fc.remove(f.id) }
                            f.fileSize == maxSize && maxSizeCount == 1 -> { nc.add(f.id); fc.remove(f.id) }
                            else -> { c.add(f.id); fc.add(f.id) }
                        }
                    }
                }
            }

            val subResult = (c - nc) + fc
            if (subResult.isNotEmpty()) {
                val nv = S[0].title.ifEmpty { "?" }
                val au = S[0].author.ifEmpty { "?" }
                detailLines.add(
                    "勾选重复-重复子组 书名=$nv 作者=$au 共${S.size}本 -> 勾选${subResult.size}个: ${subResult.sorted()}"
                )
                allResult += subResult
            }
        }

        // ── 用户自定义规则（条件-动作引擎） ──
        if (userRules.isNotEmpty()) {
            for (row in rows) {
                for (ur in userRules) {
                    if (evaluateUserRule(row, ur)) {
                        val action = ur.action ?: "check"
                        if (action == "check") {
                            allResult.add(row.id)
                        } else {
                            allResult.remove(row.id)
                        }
                    }
                }
            }
        }

        return allResult to detailLines
    }
}
