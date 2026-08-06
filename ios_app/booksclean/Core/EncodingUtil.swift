import Foundation

/// 文件编码探测工具（对齐 Android `EncodingUtil`）。
/// 探测规则：1) 检查 BOM；2) 无 BOM 时严格校验 UTF-8；3) 否则按 GB18030 兜底。
enum EncodingUtil {
    private static let DEFAULT_SAMPLE_BYTES = 8 * 1024

    /// 把编码显示名映射到 String.Encoding（iOS 原生支持 GB18030）。
    static func stringEncoding(named name: String) -> String.Encoding {
        switch name {
        case "UTF-8": return .utf8
        case "UTF-16LE": return .utf16LittleEndian
        case "UTF-16BE": return .utf16BigEndian
        case "GB18030":
            let cf = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x06320000)) // kCFStringEncodingGB_18030_2000
            return String.Encoding(rawValue: cf)
        default: return .utf8
        }
    }

    /// 探测文件编码并返回 (编码显示名, 需跳过的 BOM 字节数)。sample 为文件前若干字节。
    static func detectEncodingAndBom(sample: Data) -> (String, Int) {
        let len = sample.count
        if len >= 3 && sample[0] == 0xEF && sample[1] == 0xBB && sample[2] == 0xBF { return ("UTF-8", 3) }
        if len >= 2 && sample[0] == 0xFF && sample[1] == 0xFE { return ("UTF-16LE", 2) }
        if len >= 2 && sample[0] == 0xFE && sample[1] == 0xFF { return ("UTF-16BE", 2) }
        return looksLikeUtf8(sample) ? ("UTF-8", 0) : ("GB18030", 0)
    }

    static func detectEncodingName(sample: Data) -> String { detectEncodingAndBom(sample: sample).0 }

    /// 手写 UTF-8 合法性校验；采样末尾被截断的多字节序列不算错误。
    static func looksLikeUtf8(_ b: Data) -> Bool {
        var i = 0
        while i < b.count {
            let c = Int(b[i])
            let need: Int
            if c < 0x80 { need = 0 }
            else if c >= 0xC2 && c <= 0xDF { need = 1 }
            else if c >= 0xE0 && c <= 0xEF { need = 2 }
            else if c >= 0xF0 && c <= 0xF4 { need = 3 }
            else { return false }
            if i + need >= b.count { return true }
            for j in 1...need {
                if (Int(b[i + j]) & 0xC0) != 0x80 { return false }
            }
            i += need + 1
        }
        return true
    }

    // MARK: - 严格解码（解决 GBK 字节被 UTF-8 lenient 解码成乱码的问题）

    /// CJK 统一表意文字（含扩展 A）占比：用于中文 txt 解码质量评分。
    /// 注意：iOS 的 `String(data:encoding:.utf8)` 对非法字节是**静默丢弃**（不插入 U+FFFD），
    /// 所以单靠 replacementCharRatio 无法识别「GBK 字节被 UTF-8 当乱码」的情况；
    /// 而正确解码的中文文本 CJK 比例应明显更高，故以 CJK 占比作为主判据。
    private static func cjkCharRatio(_ s: String) -> Double {
        if s.isEmpty { return 0 }
        var cjk = 0
        for ch in s {
            guard let v = ch.unicodeScalars.first?.value else { continue }
            if (0x3400...0x9FFF).contains(v) { cjk += 1 }
        }
        return Double(cjk) / Double(s.count)
    }

    /// 严格按候选顺序尝试解码，以「CJK 内容占比」为核心判据选择最合理的解码结果。
    ///
    /// 判定逻辑（解决 iOS Foundation UTF-8 静默丢字节、不产生 U+FFFD 导致乱码的问题）：
    /// - 对所有成功解码（`String(data:encoding:)` 非 nil）的候选，计算 CJK 占比；
    /// - 真 UTF-8 中文：UTF-8 分支 CJK 高，且其字节必过 `looksLikeUtf8` → 额外 +0.2 红利，确保优先；
    /// - 真 GBK/GB18030：UTF-8 分支静默丢字节后 CJK 极低，GB18030 分支 CJK 高 → 选 GB18030；
    /// - 纯 ASCII/英文：各候选 CJK≈0，UTF-8 凭红利胜出，保持保真。
    /// 返回 (解码文本, 实际使用的编码名)。全部失败返回 ("", "")。
    static func decodeStrict(data: Data, candidates: [String]) -> (String, String) {
        var best = ("", "", -1.0)
        for name in candidates {
            let enc = stringEncoding(named: name)
            guard let s = String(data: data, encoding: enc) else { continue }
            var score = cjkCharRatio(s)
            if name == "UTF-8" && looksLikeUtf8(data) {
                score += 0.2 // 真 UTF-8 字节流红利，避免被 GB18030 误解码抢走
            }
            if score > best.2 {
                best = (s, name, score)
            }
        }
        return (best.0, best.1)
    }
}
