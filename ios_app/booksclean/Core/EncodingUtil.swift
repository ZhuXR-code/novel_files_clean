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
    ///
    /// 性能：**必须遍历 `unicodeScalars` 而非 `Character`**。`String` 的 `Character` 迭代要做
    /// grapheme cluster 断字（Unicode 边界算法），对 10 万字级预览文本比标量遍历慢 1~2 个数量级，
    /// 是「预览加载时间长（主线程卡死数秒）」的主因之一。
    /// 同时按 `sampleLimit` 只抽样前若干标量评分——判别编码不需要全文，抽样即可稳定区分。
    private static func cjkScalarRatio(_ s: String, sampleLimit: Int = 20_000) -> Double {
        var cjk = 0
        var total = 0
        for v in s.unicodeScalars {
            let x = v.value
            // 跳过 ASCII 空白/换行，避免大量排版空白稀释中文占比
            if x == 0x20 || x == 0x09 || x == 0x0A || x == 0x0D { continue }
            total += 1
            if (0x3400...0x9FFF).contains(x) { cjk += 1 }
            if total >= sampleLimit { break }
        }
        return total == 0 ? 0 : Double(cjk) / Double(total)
    }

    /// 把 Data 在「字符边界安全」的前提下裁剪：丢弃末尾可能被截断的多字节序列。
    /// 预览按固定字节数截取（如 200KB）几乎必然切断一个 UTF-8/GB18030 汉字，
    /// 残字节会让 UTF-8 解码整体失败或让评分失真，表现为「预览末尾乱码 / 整篇选错编码」。
    static func trimIncompleteTail(_ data: Data, encodingName: String) -> Data {
        guard !data.isEmpty else { return data }
        // 统一成 0 基数组，避免 Data 切片非 0 起始索引带来的下标错乱
        let bytes = [UInt8](data)
        let n = bytes.count
        // 保留前 keep 个字节
        func keep(_ count: Int) -> Data {
            count >= n ? data : Data(bytes[0..<max(0, count)])
        }
        if encodingName == "UTF-8" {
            // 回退最多 3 字节找到最后一个序列起始字节，判断该序列是否完整
            var i = n - 1
            let lower = max(0, n - 4)
            while i >= lower {
                let c = bytes[i]
                if c & 0x80 == 0 { return data }                 // ASCII 结尾，完整
                if c & 0xC0 == 0xC0 {                            // 多字节序列起始字节
                    let need: Int
                    if c & 0xE0 == 0xC0 { need = 2 }
                    else if c & 0xF0 == 0xE0 { need = 3 }
                    else if c & 0xF8 == 0xF0 { need = 4 }
                    else { return keep(i) }                      // 非法起始，直接砍掉
                    return (n - i) >= need ? data : keep(i)      // 字节不够即为截断
                }
                i -= 1                                           // 0x80...0xBF 续字节，继续回退
            }
            return data
        }
        // GB18030/GBK：双字节序列首字节 0x81...0xFE。统计末尾连续的高位字节个数，
        // 奇数说明最后一个汉字只写了一半，需要砍掉 1 字节。
        var trailing = 0
        var j = n - 1
        while j >= 0 && bytes[j] >= 0x81 && bytes[j] <= 0xFE {
            trailing += 1
            j -= 1
        }
        return trailing % 2 == 1 ? keep(n - 1) : data
    }

    /// 严格按候选顺序尝试解码，以「CJK 内容占比」为核心判据选择最合理的解码结果。
    ///
    /// 判定逻辑（解决 iOS Foundation UTF-8 静默丢字节、不产生 U+FFFD 导致乱码的问题）：
    /// - 每个候选先做「字符边界安全裁剪」，避免尾部半个汉字影响解码与评分；
    /// - 对所有成功解码的候选计算 CJK 占比（抽样，标量级遍历）；
    /// - 真 UTF-8 中文：UTF-8 分支 CJK 高，且其字节必过 `looksLikeUtf8` → +0.25 红利，确保优先；
    /// - 真 GBK/GB18030：UTF-8 分支静默丢字节后 CJK 极低，GB18030 分支 CJK 高 → 选 GB18030；
    /// - 纯 ASCII/英文：各候选 CJK≈0，UTF-8 凭红利胜出，保持保真。
    /// - 提前短路：若 UTF-8 校验通过且 CJK 占比够高，直接返回，省掉 GB18030 的整次解码。
    /// 返回 (解码文本, 实际使用的编码名)。全部失败返回 ("", "")。
    static func decodeStrict(data: Data, candidates: [String]) -> (String, String) {
        var best = ("", "", -1.0)
        // 只需判定一次：整段字节是否是合法 UTF-8（裁掉尾部残字节后判定更准）
        let utf8Safe = trimIncompleteTail(data, encodingName: "UTF-8")
        let isUtf8 = looksLikeUtf8(utf8Safe)
        for name in candidates {
            let enc = stringEncoding(named: name)
            let safe = trimIncompleteTail(data, encodingName: name)
            guard let s = String(data: safe, encoding: enc), !s.isEmpty else { continue }
            var score = cjkScalarRatio(s)
            if name == "UTF-8" && isUtf8 {
                score += 0.25 // 真 UTF-8 字节流红利，避免被 GB18030 误解码抢走
                // 合法 UTF-8 且中文密度正常：无需再试其它编码，直接返回（大幅缩短加载时间）
                if score >= 0.35 { return (s, name) }
            }
            if score > best.2 {
                best = (s, name, score)
            }
        }
        return (best.0, best.1)
    }
}
