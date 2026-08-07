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

    /// 把外部来源的 Data 复制为独立 owned 的 [UInt8]（值类型、连续内存、绝无 NSData 桥接）。
    /// 关键：security-scoped 容器文件经 FileHandle.readData 返回的 Data 可能为桥接 NSData，
    /// 对其直接做随机下标会触发 Data.subscript 的 _preconditionFailure（SIGTRAP）闪退。
    /// 此处用 withUnsafeBytes 顺序遍历复制，是唯一安全的隔离方式。
    static func toBytes(_ data: Data) -> [UInt8] {
        data.isEmpty ? [] : data.withUnsafeBytes { Array($0) }
    }

    /// 探测文件编码并返回 (编码显示名, 需跳过的 BOM 字节数)。bytes 为文件前若干字节。
    /// 入参必须为已隔离的 [UInt8]（见 toBytes），严禁直接传桥接 Data 下标访问。
    static func detectEncodingAndBom(bytes: [UInt8]) -> (String, Int) {
        let len = bytes.count
        if len >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF { return ("UTF-8", 3) }
        if len >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE { return ("UTF-16LE", 2) }
        if len >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF { return ("UTF-16BE", 2) }
        return looksLikeUtf8(bytes) ? ("UTF-8", 0) : ("GB18030", 0)
    }

    /// 兼容封装：内部先 toBytes 隔离脏 buffer 再探测。
    static func detectEncodingAndBom(sample: Data) -> (String, Int) {
        detectEncodingAndBom(bytes: toBytes(sample))
    }

    /// 兼容封装。
    static func detectEncodingName(sample: Data) -> String { detectEncodingAndBom(sample: sample).0 }

    /// 手写 UTF-8 合法性校验；采样末尾被截断的多字节序列不算错误。
    static func looksLikeUtf8(_ b: [UInt8]) -> Bool {
        var i = 0
        let count = b.count
        while i < count {
            let c = Int(b[i])
            let need: Int
            if c < 0x80 { need = 0 }
            else if c >= 0xC2 && c <= 0xDF { need = 1 }
            else if c >= 0xE0 && c <= 0xEF { need = 2 }
            else if c >= 0xF0 && c <= 0xF4 { need = 3 }
            else { return false }
            if i + need >= count { return true }
            // 关键修复：need == 0（ASCII）时 1...0 是非法 ClosedRange，
            // Swift 运行时会触发 "Range requires lowerBound <= upperBound" fatal error（brk 1 / EXC_BREAKPOINT），
            // 表现为深度扫描读取任意含 ASCII 字节的文件即闪退。
            // 必须 guard need > 0 才进入续字节校验循环。
            if need > 0 {
                for j in 1...need {
                    if (Int(b[i + j]) & 0xC0) != 0x80 { return false }
                }
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
    static func trimIncompleteTail(_ bytes: [UInt8], encodingName: String) -> Data {
        let n = bytes.count
        // 保留前 keep 个字节（返回独立 Data，不再引用原 Data）
        func keep(_ count: Int) -> Data {
            count >= n ? Data(bytes) : Data(bytes[0..<max(0, count)])
        }
        if n == 0 { return Data() }
        if encodingName == "UTF-16LE" || encodingName == "UTF-16BE" {
            // UTF-16 必须按 2 字节对齐；末尾若为孤立高代理（后缺低代理），String 解码会失败，一并砍掉。
            var keepCount = (n / 2) * 2
            if keepCount >= 2 {
                let hi: Int = encodingName == "UTF-16LE"
                    ? (Int(bytes[keepCount - 2]) | (Int(bytes[keepCount - 1]) << 8))
                    : ((Int(bytes[keepCount - 2]) << 8) | Int(bytes[keepCount - 1]))
                if (0xD800...0xDBFF).contains(hi) { keepCount -= 2 } // 孤立高代理
            }
            return keepCount >= n ? Data(bytes) : Data(bytes[0..<max(0, keepCount)])
        }
        if encodingName == "UTF-8" {
            // 回退最多 3 字节找到最后一个序列起始字节，判断该序列是否完整
            var i = n - 1
            let lower = max(0, n - 4)
            while i >= lower {
                let c = bytes[i]
                if c & 0x80 == 0 { return Data(bytes) }          // ASCII 结尾，完整
                if c & 0xC0 == 0xC0 {                            // 多字节序列起始字节
                    let need: Int
                    if c & 0xE0 == 0xC0 { need = 2 }
                    else if c & 0xF0 == 0xE0 { need = 3 }
                    else if c & 0xF8 == 0xF0 { need = 4 }
                    else { return keep(i) }                      // 非法起始，直接砍掉
                    return (n - i) >= need ? Data(bytes) : keep(i)  // 字节不够即为截断
                }
                i -= 1                                           // 0x80...0xBF 续字节，继续回退
            }
            return Data(bytes)
        }
        // GB18030/GBK：双字节序列首字节 0x81...0xFE。统计末尾连续的高位字节个数，
        // 奇数说明最后一个汉字只写了一半，需要砍掉 1 字节。
        var trailing = 0
        var j = n - 1
        while j >= 0 && bytes[j] >= 0x81 && bytes[j] <= 0xFE {
            trailing += 1
            j -= 1
        }
        return trailing % 2 == 1 ? keep(n - 1) : Data(bytes)
    }

    /// 严格按候选顺序尝试解码，以「CJK 内容占比 − 异常字符惩罚」为核心判据选择最合理的解码结果。
    ///
    /// 判定逻辑（解决 iOS Foundation UTF-8 静默丢字节、不产生 U+FFFD 导致乱码的问题）：
    /// - 每个候选先做「字符边界安全裁剪」，避免尾部半个汉字影响解码与评分；
    /// - 对所有成功解码的候选计算 CJK 占比（抽样，标量级遍历）；
    /// - 真 UTF-8 中文：UTF-8 分支 CJK 高且几乎无异常字符 → 胜出；
    /// - 真 GBK/GB18030：UTF-8 分支静默丢字节后会产生大量「非 ASCII 非 CJK」的乱码字符（被惩罚），
    ///   GB18030 分支 CJK 高且异常字符少 → 选 GB18030；
    /// - 纯 ASCII/英文：各候选 CJK≈0、异常字符≈0，UTF-8 胜出（保真）。
    /// 注意：早期版本给 UTF-8 加 +0.25 红利，反而让「GBK 误当 UTF-8 静默丢字节」的乱码方案胜出，
    /// 已移除——纯按 CJK 占比与异常字符竞争即可正确区分。
    /// 返回 (解码文本, 实际使用的编码名)。全部失败返回 ("", "")。
    static func decodeStrict(data: Data, candidates: [String]) -> (String, String) {
        // 关键防护：来自 File Provider / 外部文件夹的 Data 常是桥接的 NSData（脏 buffer），
        // 其底层 length 与实际内存可能不一致，对其直接下标/复制会触发
        // Data.subscript 越界 trap（EXC_BREAKPOINT）导致闪退。
        // 必须先用 toBytes 经 withUnsafeBytes 顺序复制为独立 [UInt8]，再全部基于 [UInt8] 处理。
        let bytes = toBytes(data)
        var best = ("", "", -1.0)
        for name in candidates {
            let enc = stringEncoding(named: name)
            let safe = trimIncompleteTail(bytes, encodingName: name)
            guard let s = String(data: safe, encoding: enc), !s.isEmpty else { continue }
            var score = cjkScalarRatio(s)
            // 异常字符惩罚：非 ASCII、非 CJK 的其它字符（乱码产物）越多，越不可能是正确编码。
            let penalty = abnormalRatio(s)
            score -= penalty * 0.8
            if score > best.2 {
                best = (s, name, score)
            }
        }
        return (best.0, best.1)
    }

    /// 异常字符（乱码产物）占比：既不是 ASCII 可打印/空白、也不在常用 CJK 区的字符。
    /// GBK 文件按 UTF-8 静默丢字节解码后，会产生大量落在私用区/特殊符号区的怪字符，此处用于惩罚。
    private static func abnormalRatio(_ s: String) -> Double {
        let sampleLimit = 20000
        var total = 0
        var abnormal = 0
        for ch in s.unicodeScalars.prefix(sampleLimit) {
            total += 1
            let v = ch.value
            let isAsciiPrintable = (v >= 0x20 && v < 0x7F) || v == 0x09 || v == 0x0A || v == 0x0D
            let isCJK = (v >= 0x4E00 && v <= 0x9FFF) || (v >= 0x3400 && v <= 0x4DBF)
                       || (v >= 0xF900 && v <= 0xFAFF) || (v >= 0x3000 && v <= 0x303F)
                       || (v >= 0xFF00 && v <= 0xFFEF)
            if !isAsciiPrintable && !isCJK {
                abnormal += 1
            }
        }
        return total == 0 ? 0 : Double(abnormal) / Double(total)
    }
}
