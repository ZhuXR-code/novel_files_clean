import Foundation

/// 简体/拼音 转换工具（对齐 Android `ChineseConverter`）。
/// 底层使用 iOS 原生 CFStringTransform，无需第三方库：
/// - 繁体→简体：ICU transform "Hant-Hans"（CoreFoundation 没有对应命名常量）
/// - 简体→繁体：ICU transform "Hans-Hant"
/// - 拼音：kCFStringTransformToLatin + kCFStringTransformStripCombiningMarks
enum ChineseConverter {
    /// 将可能含繁体字的文本转换为简体；已是简体或空串则原样返回。
    static func toSimplified(_ text: String) -> String {
        if text.isEmpty { return text }
        let m = NSMutableString(string: text)
        CFStringTransform(m, nil, "Hant-Hans" as CFString, false)
        return m as String
    }

    /// 简体→繁体。
    static func toTraditional(_ text: String) -> String {
        if text.isEmpty { return text }
        let m = NSMutableString(string: text)
        CFStringTransform(m, nil, "Hans-Hant" as CFString, false)
        return m as String
    }

    /// 生成拼音搜索字符串，格式 "全拼|首字母"。例："斗破苍穹" → "dou po cang qiong|dpcq"。
    static func toPinyin(_ text: String) -> String {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        let full = toPinyinFull(text)
        if full.isEmpty { return "" }
        var initials = ""
        for ch in text {
            if isChinese(ch) {
                let py = pinyinForChar(ch)
                if !py.isEmpty { initials.append(py[py.startIndex]) }
            }
        }
        if initials.isEmpty { return "" }
        return "\(full)|\(initials)"
    }

    private static func toPinyinFull(_ text: String) -> String {
        let m = NSMutableString(string: text)
        CFStringTransform(m, nil, kCFStringTransformToLatin, false)
        CFStringTransform(m, nil, kCFStringTransformStripCombiningMarks, false)
        // CFStringTransform 已输出空格分隔的拉丁字母；统一小写并清理多余空格
        let cleaned = (m as String)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return cleaned
    }

    private static func pinyinForChar(_ ch: Character) -> String {
        let m = NSMutableString(string: String(ch))
        CFStringTransform(m, nil, kCFStringTransformToLatin, false)
        CFStringTransform(m, nil, kCFStringTransformStripCombiningMarks, false)
        let s = (m as String).lowercased()
        return s.components(separatedBy: " ").first ?? ""
    }

    private static func isChinese(_ ch: Character) -> Bool {
        let o = ch.unicodeScalars.first!.value
        return (0x4E00...0x9FFF).contains(o) || (0x3400...0x4DBF).contains(o)
    }
}
