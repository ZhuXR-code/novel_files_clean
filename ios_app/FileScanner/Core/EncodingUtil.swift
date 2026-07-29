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
            let cf = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(kCFStringEncodingGB_18030_2000))
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
    private static func looksLikeUtf8(_ b: Data) -> Bool {
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
}
