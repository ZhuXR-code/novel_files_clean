import Foundation

/// 文件名解析结果（对齐 Android `ParsedName`）。
struct ParsedName {
    var title: String = ""
    var author: String = ""
    var progress: String = ""
    var source: String = ""
}

/// 文件名解析（对齐 PC 端 backend/regex_parser.py 的 _parse_filename_by_regex 与 _extract_source_progress，仅基于文件名）。
enum Parser {
    // 常见小说来源站点（用于从文件名方括号标签提取「来源」列）
    private static let SOURCE_SITES = [
        "废文", "海棠", "fw", "ht", "米国度", "晋江", "长佩", "刺猬猫", "豆腐", "老福特", "息壤",
        "粉笔", "鲜网", "绿茶", "寒武纪", "不可能的世界", "豆瓣阅读", "掌阅",
        "番茄", "起点", "飞卢", "纵横", "17K", "黑岩", "云起", "红袖", "潇湘书院", "米国",
        "阅文", "LOFTER", "lofter", "Po18", "po18", "FW", "HT"
    ]

    // ============ 书名/作者 正则（按顺序命中即返回） ============
    private static let RE_BOOK_AUTHOR        = RX(#"《([^》]+)》.*?(?:作家|作者)[：:]\s*(.+)"#)
    private static let RE_BOOK_BY            = RX(#"《([^》]+)》.*?[bB][yY]\s*(.+)"#)
    private static let RE_BOOK_AUTHOR2       = RX(#"《(.+?)》\s*(?:作家|作者)[：:]\s*(.+)"#)
    private static let RE_TAG_BOOK_AUTHOR    = RX(#"【[^】]+】\s*《(.+?)》\s*(?:作家|作者)[：:]\s*(.+)"#)
    private static let RE_BOOK_BY2           = RX(#"《(.+?)》\s*[bB][yY]\s*(.+)"#)
    private static let RE_NAME_BY            = RX(#"^(.+?)\s+[bB][yY]\s+(.+)"#)
    private static let RE_NAME_AUTHOR        = RX(#"^(.+?)[_\-—]\s*(?:作家|作者)[：:]?\s*(.+)"#)
    private static let RE_TAG_NAME_BY        = RX(#"^[【\[（(][^】\]）)\n]+[】\]）)]\s*(.+?)\s*[bB][yY]\s*(.+)"#)
    private static let RE_TAG_NAME_AUTHOR    = RX(#"^[【\[（(][^】\]）)\n]+[】\]）)]\s*(.+?)\s*(?:作家|作者)[：:]\s*(.+)"#)
    private static let RE_TAG_NAME_ONLY      = RX(#"^[【\[（(][^】\]）)\n]+[】\]）)]\s*(.+)"#)
    private static let RE_NAME_BY2           = RX(#"^(.+?)\s*[bB][yY]\s*(.+)"#)
    private static let RE_BRACKET_NAME_AUTHOR = RX(#"\[[^\]]+\]\s*(.+?)\s*(?:作家|作者)[：:]\s*(.+)"#)
    private static let RE_NAME_AUTHOR2        = RX(#"^(.+?)\s*(?:作家|作者)[：:]\s*(.+)"#)
    private static let RE_OPT_TAG_BOOK_AUTHOR = RX(#"^(?:\[.*?\])?\s*《(.+?)》\s*(?:作家|作者)\s*(.+?)$"#)
    private static let RE_BOOK_ONLY          = RX(#"《(.+?)》"#)
    private static let RE_TITLE_PAREN_VER    = RX(#"^(.+?)\s*[（(]\s*[\w\-]+(?:\.[\w\-]+)+\s*[）)]\s*$"#)
    private static let RE_CATEGORY           = RX(#"(?i)^(?:BG|BL|GL|GB|DM|言情|耽美|百合|同人|原创|武侠|玄幻|古言|现言|仙侠|科幻|悬疑|惊悚|轻小说|海棠|popo|废文|po18|SF)\s*(.+?)[_\-—](.+)"#)
    private static let RE_DASH_UNDER         = RX(#"^(.+?)[_\-—](.+?)$"#)
    private static let RE_TITLE_BRACKET_END  = RX(#"^(.+?)\s*\[([^\]]+)\]\s*$"#)

    // 作者后缀清洗
    private static let AUTHOR_TRAIL_BRACKET  = RX(#"\s*(?:[（(][^）)]*?(?:\d+|[更完结番外npv1V修校]+)[^）)]*?[）)]|[【\[][^】\]]*?(?:\d+|[更完结番外npv1V修校]+)[^】\]]*?[】\]])\s*$"#)
    private static let AUTHOR_TRAIL_DASH_NUM = RX(#"\s*-\d+\s*$"#)
    private static let AUTHOR_TRAIL_UPDATE   = RX(#"\s*[-—~]*更新至?\s*\d+\s*$"#)
    private static let AUTHOR_TRAIL_BUFAN    = RX(#"\s*[-—~]?补番\s*$"#)
    private static let AUTHOR_TRAIL_REVISE   = RX(#"\s*[【\[（(]修[】\]）)]\s*$"#)
    private static let AUTHOR_SUFFIX_STATUS  = RX(#"\s*(?:完结|番外|全本|完本|连载|出版|实体书|定制书|定制|校对|精校).*$"#)
    private static let AUTHOR_TRAIL_PAREN_NUM = RX(#"\s*[（(]\d+[）)]\s*$"#)
    private static let AUTHOR_TRAIL_PAREN_ANY = RX(#"[\s（(]*[）)]\s*$"#)
    private static let AUTHOR_TRAIL_PAREN_LEFT = RX(#"[\s（(]*$"#)

    private static let LATIN4 = RX(#"[a-zA-Z]{4,}"#)
    private static let KEYWORD_BLOCK = RX(#"(?i)(?:试阅|请勿|版权|删[除文]|二传|商业|仅供|公告|下载|通知|说明|使用|帮助|README|changelog|免责|侵权|联系|QQ|微信|公众号|微博)"#)

    // 热路径内联 Regex 提取为顶层常量
    private static let RE_ONLY_NUM_SYM     = RX(#"^[0-9\s.\-_#@!*&]+$"#)
    private static let RE_HAS_LATIN        = RX(#"[a-zA-Z]"#)
    private static let RE_BRACKET_SQ       = RX(#"\[([^\]]*)\]"#)
    private static let RE_BRACKET_CN       = RX(#"【([^】]*)】"#)
    private static let RE_BRACKET_PAREN_CN = RX(#"（([^）]*)）"#)
    private static let RE_BRACKET_PAREN    = RX(#"\(([^)]*)\)"#)
    private static let RE_TAIL_NUM         = RX(#"-(\d+)\s*$"#)
    private static let RE_PROGRESS_GENG    = RX(#"更\s*(\d+)"#)
    private static let RE_PROGRESS_WAN     = RX(#"完结[^\]\s]*"#)
    private static let RE_PROGRESS_STATUS  = RX(#"(?:连载|断更|暂停|烂尾|坑|锁文|锁)"#)
    private static let RE_PROGRESS_FANWAI  = RX(#"番外[^\]\s]*"#)
    private static let RE_PROGRESS_UPDATE  = RX(#"更新至?\s*(\d+)"#)

    private static let LEAD_TAG = RX(#"^[【\[（(][^】\]）)]*[】\]）)]\s*"#)

    /// 真正后缀白名单：仅剥离这些扩展名（对齐安卓 EXT_RE / PC _EXT_RE）。
    /// 注意必须是 $ 锚定的整体后缀匹配，避免误伤文件名内部的点。
    private static let _EXT_RE = RX(#"\.(txt|epub|pdf|mobi|azw|azw3|doc|docx|rtf|html|htm|zip|rar|7z|lrc|csv|json|xml|jpg|jpeg|png|gif|mp3|wav|md|fb2|cbz|cbr|djvu|chm|ppt|pptx|odt|txtx)$"#)

    /// 是否含 CJK 字符
    private static func hasCJK(_ s: String) -> Bool {
        for c in s { let o = c.unicodeScalars.first!.value; if (0x4E00...0x9FFF).contains(o) || (0x3400...0x4DBF).contains(o) { return true } }
        return false
    }
    /// 是否基本是中文（用于兜底标题判断）
    private static func isMostlyChinese(_ s: String) -> Bool {
        let cn = s.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }.count
        return cn >= 2 && !LATIN4.contains(s) && !KEYWORD_BLOCK.contains(s)
    }

    /// 从文件名（不含扩展名）解析出 书名 / 作者 / 进度 / 来源。
    static func parseFileName(_ rawName: String) -> ParsedName {
        do {
            return try parseFileNameOrThrow(rawName)
        } catch {
            LogUtil.e("Parser", "解析文件名异常 rawName=\(rawName): \(error.localizedDescription)")
            return ParsedName(title: rawName, author: "", progress: "", source: "")
        }
    }

    private static func parseFileNameOrThrow(_ rawName: String) throws -> ParsedName {
        var name = rawName
        // 仅剥离真正的扩展名（白名单），对齐安卓 Parser.kt 的 EXT_RE / PC 的 _EXT_RE。
        // 不能用 lastIndex(of: ".") 截断最后一个点——无扩展名但含点的书名
        // （如 “l.ili 的奇妙冒险”）会被误截，与安卓/PC 结果不一致。
        let extMatch = Parser._EXT_RE.firstMatch(name)
        if let rng = extMatch?.range, let r = Range(rng, in: name) { name = String(name[name.startIndex..<r.lowerBound]) }
        name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return ParsedName(title: rawName, author: "", progress: "", source: "") }
        // 超长文件名保护：.*? / .+$ 一类正则在超长串上会灾难性回溯，直接整段作书名
        // （对齐 PC 端 _parse_filename_by_regex 的 len(name) > 300 提前返回）
        if name.count > 300 { return ParsedName(title: name, author: "", progress: "", source: "") }
        // 繁体 → 简体（解析前先整体转简体，确保入库一致）
        name = ChineseConverter.toSimplified(name)

        let (title, author) = parseTitleAuthor(name)
        let (source, progress) = extractSourceProgress(name)
        return ParsedName(title: cleanTitle(title), author: author, progress: progress, source: source)
    }

    /// 书名清洗：去掉开头残留的单个标签括号。
    private static func cleanTitle(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespaces)
        while true {
            guard let m = LEAD_TAG.firstMatch(t), let r = Range(m.range, in: t) else { break }
            t = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    private static func parseTitleAuthor(_ name: String) -> (String, String) {
        if let m = RE_BOOK_AUTHOR.firstMatch(name), let t = name.sub(m.range(at: 1)), let a = name.sub(m.range(at: 2)) {
            return (t.trimmingCharacters(in: .whitespaces), cleanAuthor(a))
        }
        if let m = RE_BOOK_BY.firstMatch(name), let t = name.sub(m.range(at: 1)), let a = name.sub(m.range(at: 2)) {
            return (t.trimmingCharacters(in: .whitespaces), cleanAuthor(a))
        }
        if let m = RE_BOOK_AUTHOR2.firstMatch(name), let t = name.sub(m.range(at: 1)), let a = name.sub(m.range(at: 2)) {
            return (t.trimmingCharacters(in: .whitespaces), cleanAuthor(a))
        }
        if let m = RE_TAG_BOOK_AUTHOR.firstMatch(name), let t = name.sub(m.range(at: 1)), let a = name.sub(m.range(at: 2)) {
            return (t.trimmingCharacters(in: .whitespaces), cleanAuthor(a))
        }
        if let m = RE_BOOK_BY2.firstMatch(name), let t = name.sub(m.range(at: 1)), let a = name.sub(m.range(at: 2)) {
            return (t.trimmingCharacters(in: .whitespaces), cleanAuthor(a))
        }
        if let m = RE_NAME_BY.firstMatch(name), let t = name.sub(m.range(at: 1)), let a = name.sub(m.range(at: 2)) {
            return (t.trimmingCharacters(in: .whitespaces), cleanAuthor(a))
        }
        if let m = RE_NAME_AUTHOR.firstMatch(name), let t = name.sub(m.range(at: 1)), let a = name.sub(m.range(at: 2)) {
            return (t.trimmingCharacters(in: .whitespaces), cleanAuthor(a))
        }
        if let m = RE_TAG_NAME_BY.firstMatch(name), let t = name.sub(m.range(at: 1)), let a = name.sub(m.range(at: 2)) {
            return (t.trimmingCharacters(in: .whitespaces), cleanAuthor(a))
        }
        if let m = RE_TAG_NAME_AUTHOR.firstMatch(name), let t = name.sub(m.range(at: 1)), let a = name.sub(m.range(at: 2)) {
            return (t.trimmingCharacters(in: .whitespaces), cleanAuthor(a))
        }
        if let m = RE_TAG_NAME_ONLY.firstMatch(name), let t = name.sub(m.range(at: 1)) {
            let tt = t.trimmingCharacters(in: .whitespaces)
            if tt.count >= 2 && !RE_ONLY_NUM_SYM.contains(tt) && !tt.contains("作者") && !tt.contains("《") {
                return (tt, "")
            }
        }
        if let m = RE_NAME_BY2.firstMatch(name), let t = name.sub(m.range(at: 1)), let a = name.sub(m.range(at: 2)) {
            let tt = t.trimmingCharacters(in: .whitespaces)
            let aa = a.trimmingCharacters(in: .whitespaces)
            if !tt.hasPrefix("【") && !tt.hasPrefix("(") && !tt.hasPrefix("[") {
                return (tt, stripAuthor(aa))
            }
        }
        if let m = RE_BRACKET_NAME_AUTHOR.firstMatch(name), let t = name.sub(m.range(at: 1)), let a = name.sub(m.range(at: 2)) {
            return (t.trimmingCharacters(in: .whitespaces), cleanAuthor(a))
        }
        if let m = RE_NAME_AUTHOR2.firstMatch(name), let t = name.sub(m.range(at: 1)), let a = name.sub(m.range(at: 2)) {
            var aa = a.trimmingCharacters(in: .whitespaces)
            aa = AUTHOR_SUFFIX_STATUS.replace(aa, with: "").trimmingCharacters(in: .whitespaces)
            return (t.trimmingCharacters(in: .whitespaces), stripAuthor(aa))
        }
        if let m = RE_OPT_TAG_BOOK_AUTHOR.firstMatch(name), let t = name.sub(m.range(at: 1)), let a = name.sub(m.range(at: 2)) {
            let tt = t.trimmingCharacters(in: .whitespaces)
            let aa = a.trimmingCharacters(in: .whitespaces)
            if tt.count >= 2 && aa.count >= 2 { return (tt, stripAuthor(aa)) }
        }
        if let m = RE_BOOK_ONLY.firstMatch(name), let t = name.sub(m.range(at: 1)) {
            return (t.trimmingCharacters(in: .whitespaces), "")
        }
        if let m = RE_TITLE_PAREN_VER.firstMatch(name), let t = name.sub(m.range(at: 1)) {
            return (t.trimmingCharacters(in: .whitespaces), "")
        }
        if let m = RE_CATEGORY.firstMatch(name), let t = name.sub(m.range(at: 1)), let a = name.sub(m.range(at: 2)) {
            let tt = t.trimmingCharacters(in: .whitespaces)
            var aa = a.trimmingCharacters(in: .whitespaces)
            aa = AUTHOR_TRAIL_PAREN_NUM.replace(aa, with: "").trimmingCharacters(in: .whitespaces)
            if tt.count >= 2 { return (tt, stripAuthor(aa)) }
        }
        if let m = RE_DASH_UNDER.firstMatch(name), let t = name.sub(m.range(at: 1)), let a = name.sub(m.range(at: 2)) {
            let tt = t.trimmingCharacters(in: .whitespaces)
            var aa = a.trimmingCharacters(in: .whitespaces)
            aa = AUTHOR_TRAIL_PAREN_ANY.replace(aa, with: "")
            aa = AUTHOR_TRAIL_PAREN_NUM.replace(aa, with: "")
            aa = AUTHOR_TRAIL_PAREN_LEFT.replace(aa, with: "")
            let hasCnT = hasCJK(tt)
            let hasCnA = hasCJK(aa)
            let hasLatinA = RE_HAS_LATIN.contains(aa)
            if hasCnT && tt.count >= 2 && aa.count >= 2 && (hasCnA || hasLatinA) {
                return (tt, stripAuthor(aa))
            }
        }
        if let m = RE_TITLE_BRACKET_END.firstMatch(name), let t = name.sub(m.range(at: 1)) {
            let tt = t.trimmingCharacters(in: .whitespaces)
            if tt.count >= 2 { return (tt, "") }
        }
        // 兜底：整段基本是中文且无英文长词、非说明类文件，则整段视为书名
        if !LATIN4.contains(name) {
            let cn = name.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
            if cn >= 2 && name.count <= 60 && !KEYWORD_BLOCK.contains(name) {
                return (name.trimmingCharacters(in: .whitespaces), "")
            }
        }
        return ("", "")
    }

    /// 作者清洗：去掉「著/作者/作家/：/:」前缀，再清尾部残留。
    private static func cleanAuthor(_ raw: String) -> String {
        var a = raw.trimmingCharacters(in: .whitespaces)
        if a.hasPrefix("著") { a = String(a.dropFirst()) }
        if a.hasPrefix("作者") { a = String(a.dropFirst(2)) }
        if a.hasPrefix("作家") { a = String(a.dropFirst(2)) }
        a = a.trimmingCharacters(in: .whitespaces)
        if a.hasPrefix("：") || a.hasPrefix(":") { a = String(a.dropFirst()) }
        return stripAuthor(a.trimmingCharacters(in: .whitespaces))
    }

    /// 作者尾部清洗（循环清洗：剥离末尾所有含数字/进度词/单字母标识的括号及状态后缀）。
    private static func stripAuthor(_ raw: String) -> String {
        var a = raw.trimmingCharacters(in: .whitespaces)
        for _ in 0..<6 {
            let before = a
            a = AUTHOR_TRAIL_BRACKET.replace(a, with: "").trimmingCharacters(in: .whitespaces)
            a = AUTHOR_SUFFIX_STATUS.replace(a, with: "").trimmingCharacters(in: .whitespaces)
            a = AUTHOR_TRAIL_DASH_NUM.replace(a, with: "").trimmingCharacters(in: .whitespaces)
            a = AUTHOR_TRAIL_UPDATE.replace(a, with: "").trimmingCharacters(in: .whitespaces)
            a = AUTHOR_TRAIL_BUFAN.replace(a, with: "").trimmingCharacters(in: .whitespaces)
            a = AUTHOR_TRAIL_REVISE.replace(a, with: "").trimmingCharacters(in: .whitespaces)
            if a == before { break }
        }
        return a
    }

    /// 从文件名方括号标签中提取 来源站点 与 更新进度（对齐 PC 端 _extract_source_progress）。
    private static func extractSourceProgress(_ name: String) -> (String, String) {
        // 调用方已剥离扩展名，这里直接用整个 name（PC 端是对含扩展名的原始文件名 splitext）
        let base = name
        var brackets: [String] = []
        brackets.append(contentsOf: RE_BRACKET_SQ.allGroup1(base))
        brackets.append(contentsOf: RE_BRACKET_CN.allGroup1(base))
        brackets.append(contentsOf: RE_BRACKET_PAREN_CN.allGroup1(base))
        brackets.append(contentsOf: RE_BRACKET_PAREN.allGroup1(base))

        if brackets.isEmpty {
            if let t = RE_TAIL_NUM.group(base, 1) { return ("", t) }
            return ("", "")
        }

        var source = "", progress = ""
        for content in brackets {
            if source.isEmpty {
                for site in SOURCE_SITES where !site.isEmpty && content.contains(site) {
                    source = site; break
                }
            }
            if progress.isEmpty, let gm = RE_PROGRESS_GENG.group(content, 1) { progress = gm }
            if progress.isEmpty, let wm = RE_PROGRESS_WAN.firstMatch(content) { progress = content.sub(wm.range) ?? "" }
            if progress.isEmpty, let fw = RE_PROGRESS_FANWAI.firstMatch(content) { progress = content.sub(fw.range) ?? "" }
            if progress.isEmpty, let om = RE_PROGRESS_STATUS.firstMatch(content) { progress = content.sub(om.range) ?? "" }
            if progress.isEmpty, let tail = RE_TAIL_NUM.group(base, 1) { progress = tail }
        }
        if progress.isEmpty, let tail = RE_TAIL_NUM.group(base, 1) { progress = tail }
        if progress.isEmpty, let um = RE_PROGRESS_UPDATE.group(base, 1) { progress = um }
        return (source, progress)
    }
}

private extension String {
    /// NSRange → Range<String.Index>（安全解包，避免强制解包崩溃；当前 Parser 内统一使用 String.sub）。
    func range(from ns: NSRange) -> Range<String.Index>? {
        return Range(ns, in: self)
    }
}
