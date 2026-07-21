package com.filescanner.app.util

/**
 * 文件名解析结果。作者 / 进度 / 来源 可能为空。
 *
 * 解析逻辑对齐 PC 端 backend/regex_parser.py 的 _parse_filename_by_regex（书名/作者）
 * 与 _extract_source_progress（来源/进度），仅基于文件名，不读取文件内容。
 */
data class ParsedName(
    val title: String,
    val author: String,
    val progress: String,
    val source: String
)

object Parser {
    // 常见小说来源站点（用于从文件名方括号标签提取“来源”列），对齐 PC 端 SOURCE_SITES
    private val SOURCE_SITES = listOf(
        "废文", "海棠", "晋江", "长佩", "刺猬猫", "豆腐", "老福特", "息壤",
        "粉笔", "鲜网", "绿茶", "寒武纪", "不可能的世界", "豆瓣阅读", "掌阅",
        "番茄", "起点", "飞卢", "纵横", "17K", "黑岩", "云起", "红袖", "潇湘书院",
        "阅文", "LOFTER", "lofter", "Po18", "po18", "FW", "HT"
    )

    // 中文范围（等价 PC 端 [\u4e00-\u9fff]，用字面区间避免源码转义歧义）
    private val CN_REGEX = Regex("[一-龥]")

    // ============ 书名/作者 正则（对齐 PC 端 _parse_filename_by_regex，按顺序命中即返回） ============
    private val RE_BOOK_AUTHOR = Regex("""《([^》]+)》.*?作者[：:]\s*(.+)""")
    private val RE_BOOK_BY = Regex("""《([^》]+)》.*?[bB][yY]\s*(.+)""")
    private val RE_BOOK_AUTHOR2 = Regex("""《(.+?)》\s*作者[：:]\s*(.+)""")
    private val RE_TAG_BOOK_AUTHOR = Regex("""【[^】]+】\s*《(.+?)》\s*作者[：:]\s*(.+)""")
    private val RE_BOOK_BY2 = Regex("""《(.+?)》\s*[bB][yY]\s*(.+)""")
    private val RE_NAME_BY = Regex("""^(.+?)\s+[bB][yY]\s+(.+)""")
    private val RE_NAME_AUTHOR = Regex("""^(.+?)[_\-—]\s*作者[：:]?\s*(.+)""")
    private val RE_TAG_NAME_BY = Regex("""^[【\[(][^】\])\n]+[】\])]\s*(.+?)\s*[bB][yY]\s*(.+)""")
    private val RE_TAG_NAME_AUTHOR = Regex("""^[【\[(][^】\])\n]+[】\])]\s*(.+?)\s*作者[：:]\s*(.+)""")
    private val RE_TAG_NAME_ONLY = Regex("""^[【\[(][^】\])\n]+[】\])]\s*(.+)""")
    private val RE_NAME_BY2 = Regex("""^(.+?)\s*[bB][yY]\s*(.+)""")
    private val RE_BRACKET_NAME_AUTHOR = Regex("""\[[^\]]+\]\s*(.+?)\s*作者[：:]\s*(.+)""")
    private val RE_NAME_AUTHOR2 = Regex("""^(.+?)\s*作者[：:]\s*(.+)""")
    private val RE_OPT_TAG_BOOK_AUTHOR = Regex("""^(?:\[.*?\])?\s*《(.+?)》\s*作者\s*(.+?)""")
    private val RE_BOOK_ONLY = Regex("""《(.+?)》""")
    private val RE_TITLE_PAREN_VER = Regex("""^(.+?)\s*[（(]\s*[\w\-]+(?:\.[\w\-]+)+\s*[）)]\s*$""")
    private val RE_CATEGORY = Regex("""^(?:BG|BL|GL|GB|DM|言情|耽美|百合|同人|原创|武侠|玄幻|古言|现言|仙侠|科幻|悬疑|惊悚|轻小说|海棠|popo|废文|po18|SF)\s*(.+?)[_\-—](.+)""")
    private val RE_DASH_UNDER = Regex("""^(.+?)[_\-—](.+?)""")
    private val RE_TITLE_BRACKET_END = Regex("""^(.+?)\s*\[([^\]]+)\]\s*$""")

    // 作者后缀清洗（对齐 PC 端 _name_worker 的两次正则替换）
    private val AUTHOR_TRAIL_BRACKET = Regex("""\s*[\[（][^\]）]*?(?:\d+|[更完结npv1V]+)[^\]）]*?[\]）]\s*$""")
    private val AUTHOR_TRAIL_DASH_NUM = Regex("""\s*-\d+\s*$""")
    // 仅用于“书名 作者：xxx”场景的后缀（完结/番外/连载…），以及作者尾部残留的“精校/校对”等清洗
    private val AUTHOR_SUFFIX_STATUS = Regex("""\s*(?:完结|番外|全本|完本|连载|出版|实体书|定制书|定制|校对|精校).*$""")
    // 合集/分类前缀里作者尾部残留的（数字）
    private val AUTHOR_TRAIL_PAREN_NUM = Regex("""\s*[（(]\d+[）)]\s*$""")
    private val AUTHOR_TRAIL_PAREN_ANY = Regex("""[\s（(]*[）)]\s*$""")
    private val AUTHOR_TRAIL_PAREN_LEFT = Regex("""[\s（(]*$""")

    private val LATIN4 = Regex("""[a-zA-Z]{4,}""")
    // 用内联标志 (?i) 替代 RegexOption.IGNORECASE：等价语义，且不依赖该环境下不可见的 RegexOption 符号
    private val KEYWORD_BLOCK = Regex("""(?i)(?:试阅|请勿|版权|删[除文]|二传|商业|仅供|公告|下载|通知|说明|使用|帮助|README|changelog|免责|侵权|联系|QQ|微信|公众号|微博)""")

    // ===== 热路径内联 Regex 提取为顶层常量（性能：每条文件解析都会调用，避免重复 new Regex）=====
    private val RE_ONLY_NUM_SYM = Regex("""^[0-9\s.\-_#@!*&]+$""")
    private val RE_HAS_LATIN = Regex("""[a-zA-Z]""")
    private val RE_BRACKET_SQ = Regex("""\[([^\]]*)\]""")
    private val RE_BRACKET_CN = Regex("""【([^】]*)】""")
    // 兼容圆括号（全角/半角）：常见文件名如「《书名》作者：xxx（更50）（d）」用圆括号标进度/标识。
    // 对齐 PC 端 _extract_source_progress（memory 12890424 已修复 PC 端识别圆括号）。
    private val RE_BRACKET_PAREN_CN = Regex("""（([^）]*)）""")
    private val RE_BRACKET_PAREN = Regex("""\(([^)]*)\)""")
    private val RE_TAIL_NUM = Regex("""-(\d+)\s*$""")
    private val RE_PROGRESS_GENG = Regex("""更\s*(\d+)""")
    private val RE_PROGRESS_WAN = Regex("""完结[^\]\s]*""")
    private val RE_PROGRESS_STATUS = Regex("""(?:连载|断更|暂停|烂尾|坑|锁文|锁)""")

    /**
     * 从文件名（不含扩展名）解析出 书名 / 作者 / 进度 / 来源。
     */
    fun parseFileName(rawName: String): ParsedName {
        var name = rawName
        val dot = name.lastIndexOf('.')
        if (dot > 0) name = name.substring(0, dot)
        name = name.trim()
        if (name.isEmpty()) return ParsedName(rawName, "", "", "")

        val (title, author) = parseTitleAuthor(name)
        val (source, progress) = extractSourceProgress(name)
        return ParsedName(title, author, progress, source)
    }

    /**
     * 解析 书名 / 作者，逻辑与 PC 端 _parse_filename_by_regex 一致（命中即返回）。
     * 返回 Pair(书名, 作者)，作者为空字符串表示未解析出。
     */
    private fun parseTitleAuthor(name: String): Pair<String, String> {
        var m: MatchResult?

        m = RE_BOOK_AUTHOR.find(name)
        if (m != null) return m.groupValues[1].trim() to cleanAuthor(m.groupValues[2])

        m = RE_BOOK_BY.find(name)
        if (m != null) return m.groupValues[1].trim() to cleanAuthor(m.groupValues[2])

        m = RE_BOOK_AUTHOR2.find(name)
        if (m != null) return m.groupValues[1].trim() to cleanAuthor(m.groupValues[2])

        m = RE_TAG_BOOK_AUTHOR.find(name)
        if (m != null) return m.groupValues[1].trim() to cleanAuthor(m.groupValues[2])

        m = RE_BOOK_BY2.find(name)
        if (m != null) return m.groupValues[1].trim() to cleanAuthor(m.groupValues[2])

        m = RE_NAME_BY.find(name)
        if (m != null) return m.groupValues[1].trim() to cleanAuthor(m.groupValues[2])

        m = RE_NAME_AUTHOR.find(name)
        if (m != null) return m.groupValues[1].trim() to cleanAuthor(m.groupValues[2])

        m = RE_TAG_NAME_BY.find(name)
        if (m != null) return m.groupValues[1].trim() to cleanAuthor(m.groupValues[2])

        m = RE_TAG_NAME_AUTHOR.find(name)
        if (m != null) return m.groupValues[1].trim() to cleanAuthor(m.groupValues[2])

        m = RE_TAG_NAME_ONLY.find(name)
        if (m != null) {
            val t = m.groupValues[1].trim()
            if (t.length >= 2 && !Regex("""^[0-9\s.\-_#@!*&]+$""").matches(t) && "作者" !in t && "《" !in t) {
                return t to ""
            }
        }

        m = RE_NAME_BY2.find(name)
        if (m != null) {
            val t = m.groupValues[1].trim()
            val a = m.groupValues[2].trim()
            if (!t.startsWith("【") && !t.startsWith("(") && !t.startsWith("[")) {
                return t to stripAuthor(a)
            }
        }

        m = RE_BRACKET_NAME_AUTHOR.find(name)
        if (m != null) return m.groupValues[1].trim() to cleanAuthor(m.groupValues[2])

        m = RE_NAME_AUTHOR2.find(name)
        if (m != null) {
            val t = m.groupValues[1].trim()
            var a = m.groupValues[2].trim()
            a = AUTHOR_SUFFIX_STATUS.replace(a, "").trim()
            return t to stripAuthor(a)
        }

        m = RE_OPT_TAG_BOOK_AUTHOR.find(name)
        if (m != null) {
            val t = m.groupValues[1].trim()
            val a = m.groupValues[2].trim()
            if (t.length >= 2 && a.length >= 2) return t to stripAuthor(a)
        }

        m = RE_BOOK_ONLY.find(name)
        if (m != null) return m.groupValues[1].trim() to ""

        m = RE_TITLE_PAREN_VER.find(name)
        if (m != null) return m.groupValues[1].trim() to ""

        m = RE_CATEGORY.find(name)
        if (m != null) {
            val t = m.groupValues[1].trim()
            var a = m.groupValues[2].trim()
            a = AUTHOR_TRAIL_PAREN_NUM.replace(a, "").trim()
            if (t.length >= 2) return t to stripAuthor(a)
        }

        m = RE_DASH_UNDER.find(name)
        if (m != null) {
            val t = m.groupValues[1].trim()
            var a = m.groupValues[2].trim()
            a = AUTHOR_TRAIL_PAREN_ANY.replace(a, "")
            a = AUTHOR_TRAIL_PAREN_NUM.replace(a, "")
            a = AUTHOR_TRAIL_PAREN_LEFT.replace(a, "")
            val hasCnT = CN_REGEX.find(t) != null
            val hasCnA = CN_REGEX.find(a) != null
            val hasLatinA = RE_HAS_LATIN.find(a) != null
            if (hasCnT && t.length >= 2 && a.length >= 2 && (hasCnA || hasLatinA)) {
                return t to stripAuthor(a)
            }
        }

        m = RE_TITLE_BRACKET_END.find(name)
        if (m != null) {
            val t = m.groupValues[1].trim()
            if (t.length >= 2) return t to ""
        }

        // 兜底：整段基本是中文且无英文长词、非说明类文件，则整段视为书名
        if (LATIN4.find(name) == null) {
            val cnCount = CN_REGEX.findAll(name).count()
            if (cnCount >= 2 && name.length <= 60 && KEYWORD_BLOCK.find(name) == null) {
                return name.trim() to ""
            }
        }

        return "" to ""
    }

    /** 作者清洗：去掉“著/作者/：/：”前缀，并清掉尾部的（数字）/ -数字 等残留。 */
    private fun cleanAuthor(raw: String): String {
        var a = raw.trim()
        a = a.removePrefix("著").removePrefix("作者").trim()
        a = a.removePrefix("：").removePrefix(":").trim()
        return stripAuthor(a)
    }

    /** 作者尾部清洗（对齐 PC 端 _name_worker 的循环清洗：剥离末尾所有含数字/进度词/单字母标识的括号及状态后缀）。 */
    private fun stripAuthor(raw: String): String {
        var a = raw.trim()
        // 反复清洗：先去状态后缀（如 精校/校对），再剥离末尾括号（含数字/进度词），
        // 直到不再变化，确保「（更50）精校」这类“括号+后缀”组合被完全清掉。
        repeat(6) {
            val before = a
            a = AUTHOR_TRAIL_BRACKET.replace(a, "").trim()
            a = AUTHOR_SUFFIX_STATUS.replace(a, "").trim()
            a = AUTHOR_TRAIL_DASH_NUM.replace(a, "").trim()
            if (a == before) return@repeat
        }
        return a
    }

    /**
     * 从文件名方括号标签中提取 来源站点 与 更新进度（对齐 PC 端 _extract_source_progress）。
     * 返回 Pair(来源, 进度)。
     */
    private fun extractSourceProgress(name: String): Pair<String, String> {
        val base = name.substringBeforeLast('.', name)
        val brackets = mutableListOf<String>()
        RE_BRACKET_SQ.findAll(base).forEach { brackets.add(it.groupValues[1]) }
        RE_BRACKET_CN.findAll(base).forEach { brackets.add(it.groupValues[1]) }
        RE_BRACKET_PAREN_CN.findAll(base).forEach { brackets.add(it.groupValues[1]) }
        RE_BRACKET_PAREN.findAll(base).forEach { brackets.add(it.groupValues[1]) }

        if (brackets.isEmpty()) {
            val tail = RE_TAIL_NUM.find(base)
            return "" to (tail?.groupValues?.get(1) ?: "")
        }

        var source = ""
        var progress = ""
        for (content in brackets) {
            if (source.isEmpty()) {
                for (site in SOURCE_SITES) {
                    if (site.isNotEmpty() && content.contains(site)) {
                        source = site
                        break
                    }
                }
            }
            if (progress.isEmpty()) {
                val gm = RE_PROGRESS_GENG.find(content)
                if (gm != null) progress = gm.groupValues[1]
            }
            if (progress.isEmpty()) {
                val wm = RE_PROGRESS_WAN.find(content)
                if (wm != null) progress = wm.value
            }
            if (progress.isEmpty()) {
                val tail = RE_TAIL_NUM.find(base)
                if (tail != null) progress = tail.groupValues[1]
            }
            if (progress.isEmpty()) {
                val om = RE_PROGRESS_STATUS.find(content)
                if (om != null) progress = om.value
            }
        }
        if (progress.isEmpty()) {
            val tail = RE_TAIL_NUM.find(base)
            if (tail != null) progress = tail.groupValues[1]
        }
        return source to progress
    }
}
