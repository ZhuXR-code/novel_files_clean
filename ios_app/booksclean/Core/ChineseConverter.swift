import Foundation

/// 简体/拼音 转换工具（对齐 Android `ChineseConverter`）。
/// 底层使用 iOS 原生 CFStringTransform，无需第三方库：
/// - 繁体→简体：ICU transform "Hant-Hans"（CoreFoundation 没有对应命名常量）
/// - 简体→繁体：ICU transform "Hans-Hant"
/// - 拼音：kCFStringTransformToLatin + kCFStringTransformStripCombiningMarks
enum ChineseConverter {
    /// 将可能含繁体字的文本转换为简体；已是简体或空串则原样返回。
    /// 性能：扫描热路径（每个文件名都会调用）。若文本不含 CJK 字符则根本无需执行
    /// 昂贵的 ICU transform，直接原样返回，可省下大量纯英文/数字文件名的转换开销。
    static func toSimplified(_ text: String) -> String {
        if text.isEmpty { return text }
        if !hasCJKCharacters(text) { return text }
        let m = NSMutableString(string: text)
        CFStringTransform(m, nil, "Hant-Hans" as CFString, false)
        return m as String
    }

    /// 简体→繁体。
    static func toTraditional(_ text: String) -> String {
        if text.isEmpty { return text }
        if !hasCJKCharacters(text) { return text }
        let m = NSMutableString(string: text)
        CFStringTransform(m, nil, "Hans-Hant" as CFString, false)
        return m as String
    }

    /// 生成拼音搜索字符串，格式 "全拼|首字母"。例："斗破苍穹" → "dou po cang qiong|dpcq"。
    /// 优化：整串只做 **一次** CFStringTransform（toLatin + strip），从结果中同时取全拼与首字母，
    /// 不再对每个汉字单独 transform（旧实现逐字 transform，10 字书名要 20 次 ICU 调用，
    /// 在扫描 20w 文件时积少成多成为明显瓶颈）。CFStringTransform 对非中文字母/数字会原样保留，
    /// 仅中文才转拼音，故首字母提取只需取每个空格分隔 token 的首字符即可。
    static func toPinyin(_ text: String) -> String {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        let m = NSMutableString(string: text)
        CFStringTransform(m, nil, kCFStringTransformToLatin, false)
        CFStringTransform(m, nil, kCFStringTransformStripCombiningMarks, false)
        let tokens = (m as String)
            .lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
        if tokens.isEmpty { return "" }
        let full = tokens.joined(separator: " ")
        // 首字母 = 每个 token 的首字符拼接（非中文 token 取其首字母，也兼容英文/数字前缀）
        let initials = tokens.compactMap { $0.first }.map { String($0) }.joined()
        return "\(full)|\(initials)"
    }

    private static func hasCJKCharacters(_ text: String) -> Bool {
        for c in text.unicodeScalars {
            let o = c.value
            if (0x4E00...0x9FFF).contains(o) || (0x3400...0x4DBF).contains(o) { return true }
        }
        return false
    }
}
