import Foundation

/// 轻量正则封装，行为对齐 Android 端 Kotlin 的 `Regex`（默认不匹配换行，`(?i)` 内联忽略大小写可用）。
struct RX {
    let re: NSRegularExpression

    init(_ pattern: String, options: NSRegularExpression.Options = []) {
        // 解析失败（如空模式）时回退为空正则，避免崩溃
        re = (try? NSRegularExpression(pattern: pattern, options: options)) ?? (try! NSRegularExpression(pattern: "a^"))
    }

    /// 返回首个整体匹配（不为 nil 即含匹配）
    func firstMatch(_ s: String) -> NSTextCheckingResult? {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
    }

    /// 提取第 group 个捕获组（group 默认 0 = 整体匹配文本）
    func group(_ s: String, _ group: Int = 0) -> String? {
        guard let m = firstMatch(s), m.numberOfRanges > group,
              let r = Range(m.range(at: group), in: s) else { return nil }
        return String(s[r])
    }

    /// 是否包含匹配
    func contains(_ s: String) -> Bool { firstMatch(s) != nil }

    /// 所有匹配的捕获组 1 列表（用于方括号内容提取）
    func allGroup1(_ s: String) -> [String] {
        re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
            guard m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) else { return nil }
            return String(s[r])
        }
    }

    /// 替换（对齐 Kotlin `Regex.replace`，替换全部）
    func replace(_ s: String, with template: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }
}

extension String {
    /// 按 NSRange 截取子串
    func sub(_ range: NSRange) -> String? {
        guard let r = Range(range, in: self) else { return nil }
        return String(self[r])
    }
}
