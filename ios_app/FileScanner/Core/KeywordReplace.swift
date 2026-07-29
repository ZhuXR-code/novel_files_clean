import Foundation

/// 关键词替换工具（对齐 PC 端 backend/keyword_replace.py）。
enum KeywordReplace {
    static let SCOPE_SCAN = "scan"   // 扫描阶段：作用于文件名
    static let SCOPE_PARSE = "parse" // 解析阶段：作用于 书名/作者/进度/来源

    /// 按规则顺序对文本依次执行「精确字符串替换」，pattern 命中即整段替换为 replacement（空串=删除）。
    static func applyRules(_ text: String?, _ rules: [KeywordReplaceRule]) -> String? {
        guard let text = text, !text.isEmpty, !rules.isEmpty else { return text }
        var result = text
        for r in rules where !r.pattern.isEmpty {
            result = result.replacingOccurrences(of: r.pattern, with: r.replacement)
        }
        return result
    }

    /// 预置的默认关键词替换规则（作用域=扫描阶段，作用于文件名）。仅在规则表为空时写入一次。
    static let DEFAULT_KEYWORD_RULES: [KeywordReplaceRule] = [
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "[草2莓]", replacement: "", sortOrder: 1),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【草2莓", replacement: "", sortOrder: 2),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【草2莓】", replacement: "", sortOrder: 3),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "[草 莓]", replacement: "", sortOrder: 4),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "[草 莓", replacement: "", sortOrder: 5),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【lili】", replacement: "", sortOrder: 6),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "（l.i.）", replacement: "", sortOrder: 7),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "(l.i.）", replacement: "", sortOrder: 8),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "（l.i.)", replacement: "", sortOrder: 9),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "(l.i.)", replacement: "", sortOrder: 10),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "..txt", replacement: ".txt", sortOrder: 11),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【草莓】", replacement: "", sortOrder: 12),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【草 莓", replacement: "", sortOrder: 13),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【＋V信kxee6699】", replacement: "", sortOrder: 14),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: ".3167 937770", replacement: "", sortOrder: 15),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【颜3167 937770", replacement: "", sortOrder: 16),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【Q主caomeiの企鹅3167 937770】", replacement: "", sortOrder: 17),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【Q主caomei】", replacement: "", sortOrder: 18),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "_caomeiの企鹅3167 937770_", replacement: "", sortOrder: 19),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "（caomeiの企鹅3167 937770", replacement: "", sortOrder: 20),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "(caomeiの企鹅3167 937770", replacement: "", sortOrder: 21),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【qzcaomeiの企鹅3167 937770", replacement: "", sortOrder: 22),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: ".QZcaomeiの企鹅3167 937770", replacement: "", sortOrder: 23),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "_caomeiの企鹅3167 937770", replacement: "", sortOrder: 24),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: ".caomeiの企鹅3167 937770", replacement: "", sortOrder: 25),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "の企鹅3167 937770", replacement: "", sortOrder: 26),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "[3167 937770]", replacement: "", sortOrder: 27),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "[3167 937770", replacement: "", sortOrder: 28),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "3167937770", replacement: "", sortOrder: 29),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "_3167 937770", replacement: "", sortOrder: 30),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "（颜3167 937770", replacement: "", sortOrder: 31),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【3167 937770]", replacement: "", sortOrder: 32),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "_.txt", replacement: ".txt", sortOrder: 33),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【昭昭明月BG】", replacement: "", sortOrder: 34),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【昭昭明月BL】", replacement: "", sortOrder: 35),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【推荐】", replacement: "", sortOrder: 36),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【全本校对】", replacement: "", sortOrder: 37),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【全本精校】", replacement: "", sortOrder: 38),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【BL】", replacement: "", sortOrder: 39),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【BG】", replacement: "", sortOrder: 40),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【YLW】", replacement: "", sortOrder: 41),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "『推』", replacement: "", sortOrder: 42),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【YLW连载】", replacement: "", sortOrder: 43),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【棠】", replacement: "", sortOrder: 44),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【公众号：推文日记】", replacement: "", sortOrder: 45),
        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: "【书香门第★九落】", replacement: "", sortOrder: 46)
    ]
}
