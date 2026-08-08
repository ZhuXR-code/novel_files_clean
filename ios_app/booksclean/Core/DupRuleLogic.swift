import Foundation

/// 自定义规则评估 / 内置五则规则计算的纯逻辑（对齐 Android `DupRuleLogic`，不依赖 UI / 数据库）。
enum DupRuleLogic {

    /// 评估一条用户自定义规则是否命中该行（所有条件「且」满足）。
    static func evaluateUserRule(_ row: DuplicateRow, _ rule: DupRuleConfig) -> Bool {
        guard let json = rule.conditions else { return false }
        guard let conditions = parseUserConditions(json), !conditions.isEmpty else { return false }
        for cond in conditions {
            if !evalSingleCondition(row, cond) { return false }
        }
        return true
    }

    /// 解析用户自定义条件的 JSON 字符串。新格式 [{"field","regex"}]，兼容旧格式 [{"field","op","value"}]。
    static func parseUserConditions(_ json: String) -> [[String: String]]? {
        if json.trimmingCharacters(in: .whitespaces).isEmpty || json == "[]" { return [] }
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        var items: [[String: String]] = []
        for obj in arr {
            guard let field = obj["field"] as? String, !field.isEmpty else { continue }
            let regex: String
            if let r = obj["regex"] as? String {
                regex = r
            } else {
                let op = (obj["op"] as? String) ?? "eq"
                let value = (obj["value"] as? String) ?? ""
                regex = oldOpToRegex(op, value)
            }
            items.append(["field": field, "regex": regex])
        }
        return items
    }

    /// 把旧格式 op+value 转正则。
    static func oldOpToRegex(_ op: String, _ value: String) -> String {
        if value.isEmpty { return "" }
        let esc = NSRegularExpression.escapedPattern(for: value)
        switch op {
        case "contains": return esc
        case "not_contains": return "(?s)^(?:(?!\(esc)).)*$"
        case "starts_with": return "^\(esc)"
        case "ends_with": return "\(esc)$"
        case "eq": return "^\(esc)$"
        case "neq": return "(?s)^(?:(?!\(esc)).)*$"
        case "regex": return value
        default: return ""
        }
    }

    /// 评估单条条件：对所选字段用正则匹配。
    static func evalSingleCondition(_ row: DuplicateRow, _ cond: [String: String]) -> Bool {
        guard let field = cond["field"], let pattern = cond["regex"], !pattern.isEmpty else { return false }
        let actual: String
        switch field {
        case "file_name": actual = row.fileName
        case "novel_name": actual = row.title
        case "author": actual = row.author
        case "progress": actual = row.progress
        case "source": actual = row.source
        case "file_size": actual = String(row.fileSize)
        case "created_date": actual = String(row.createdAt)
        default: return true
        }
        return (try? NSRegularExpression(pattern: pattern)).map { $0.firstMatch(in: actual, range: NSRange(actual.startIndex..., in: actual)) != nil } ?? false
    }

    // ===================== 内置规则（五则）评估所需的纯工具 =====================

    private static let COMPLETION_KW = ["完结", "完本", "全本", "全集", "完整", "全套", "全集版"]
    private static let FANWAI_RE = RX(#"^完结\+(?:(\d+(?:\.\d+)?)番外|番外(\d+(?:\.\d+)?))$"#)

    private static func hasCjk(_ s: String?) -> Bool {
        guard let s = s, !s.isEmpty else { return false }
        for c in s { let o = c.unicodeScalars.first!.value; if (0x4E00...0x9FFF).contains(o) || (0x3400...0x4DBF).contains(o) { return true } }
        return false
    }

    /// 若进度为纯数字（可选小数、可选尾随 %），返回 Double，否则 nil。
    private static func progressValue(_ s: String?) -> Double? {
        let t = (s ?? "").trimmingCharacters(in: .whitespaces)
        if t.isEmpty || hasCjk(t) { return nil }
        guard let m = RX(#"^(\d+(?:\.\d+)?)\s*%?$"#).firstMatch(t) else { return nil }
        return Double(t.sub(m.range(at: 1)) ?? "")
    }

    /// 若进度匹配「完结+N番外」或「完结+番外N」，返回数字 N，否则 nil。
    private static func fanwaiValue(_ s: String?) -> Double? {
        let t = (s ?? "").trimmingCharacters(in: .whitespaces)
        guard let m = FANWAI_RE.firstMatch(t) else { return nil }
        let a = t.sub(m.range(at: 1)) ?? ""
        let b = t.sub(m.range(at: 2)) ?? ""
        return Double(a.isEmpty ? b : a)
    }

    private static func subKey(_ author: String, _ title: String) -> String {
        return "\(author.trimmingCharacters(in: .whitespaces).lowercased())\u{0000}\(title.trimmingCharacters(in: .whitespaces).lowercased())"
    }

    /// 计算「应勾选重复文件」的集合（纯函数，与 Android 一致）。
    static func computeDuplicateChecks(
        _ rows: [DuplicateRow],
        _ enabledBuiltinKeys: Set<String>,
        _ userRules: [DupRuleConfig]
    ) -> (Set<Int64>, [String]) {
        let subgroups = Dictionary(grouping: rows) { subKey($0.author, $0.title) }
        var allResult = Set<Int64>()
        var detailLines: [String] = []

        for (_, S) in subgroups {
            if S.count < 2 { continue }
            var c = Set<Int64>(), nc = Set<Int64>(), fc = Set<Int64>()

            // 规则 1：完全相等去重
            if enabledBuiltinKeys.contains("rule1") {
                let exact = Dictionary(grouping: S) { "\($0.fileSize)\u{0000}\($0.progress.trimmingCharacters(in: .whitespaces))" }
                for (_, g) in exact where g.count >= 2 {
                    let newest = g.max { a, b in
                        // 优先按文件真实修改时间(fileDate)判断最新；缺失时回退到扫描入库时间(createdAt)。
                        let ca = a.fileDate != 0 ? a.fileDate : a.createdAt
                        let cb = b.fileDate != 0 ? b.fileDate : b.createdAt
                        return ca < cb || (ca == cb && a.id < b.id)
                    }!
                    nc.insert(newest.id)
                    for f in g where f.id != newest.id { c.insert(f.id); fc.insert(f.id) }
                }
            }

            let numericFiles = S.filter { progressValue($0.progress) != nil }
            let chineseFiles = S.filter { hasCjk($0.progress) }

            // 规则 2：纯数字进度对比
            if enabledBuiltinKeys.contains("rule2"), numericFiles.count >= 2 {
                let maxVal = numericFiles.compactMap { progressValue($0.progress) }.max()!
                let maxFiles = numericFiles.filter { progressValue($0.progress) == maxVal }
                maxFiles.forEach { nc.insert($0.id) }
                for f in numericFiles where progressValue(f.progress) != maxVal { c.insert(f.id); fc.insert(f.id) }
            }

            // 规则 3A：含中文进度保护
            if enabledBuiltinKeys.contains("rule3a") {
                chineseFiles.forEach { nc.insert($0.id); fc.remove($0.id) }
            }

            // 规则 3B：完结特例
            if enabledBuiltinKeys.contains("rule3b"), !numericFiles.isEmpty {
                let maxNumVal = numericFiles.compactMap { progressValue($0.progress) }.max()!
                let maxNumFiles = numericFiles.filter { progressValue($0.progress) == maxNumVal }
                let completionFiles = S.filter { f in COMPLETION_KW.contains(where: { f.fileName.contains($0) }) }
                if !completionFiles.isEmpty {
                    let minCompletionSize = completionFiles.map { $0.fileSize }.min()!
                    if maxNumFiles.allSatisfy({ $0.fileSize < minCompletionSize }) {
                        maxNumFiles.forEach { fc.insert($0.id) }
                    }
                }
            }

            let maxSize = S.map { $0.fileSize }.max() ?? 0
            let maxSizeCount = S.filter { $0.fileSize == maxSize }.count

            // 规则 4：最大文件不勾选
            if enabledBuiltinKeys.contains("rule4"), maxSizeCount == 1 {
                S.forEach { if $0.fileSize == maxSize { nc.insert($0.id); fc.remove($0.id) } }
            }

            // 规则 5：完结+N番外 / 完结+番外N 去重
            if enabledBuiltinKeys.contains("rule5") {
                let fanwai = S.filter { fanwaiValue($0.progress) != nil }
                if !fanwai.isEmpty {
                    let maxN = fanwai.compactMap { fanwaiValue($0.progress) }.max()!
                    let maxNIds = Set(fanwai.filter { fanwaiValue($0.progress) == maxN }.map { $0.id })
                    for f in fanwai {
                        if maxNIds.contains(f.id) { nc.insert(f.id); fc.remove(f.id) }
                        else if f.fileSize == maxSize && maxSizeCount == 1 { nc.insert(f.id); fc.remove(f.id) }
                        else { c.insert(f.id); fc.insert(f.id) }
                    }
                }
            }

            let subResult = (c.subtracting(nc)).union(fc)
            if !subResult.isEmpty {
                let nv = S[0].title.isEmpty ? "?" : S[0].title
                let au = S[0].author.isEmpty ? "?" : S[0].author
                detailLines.append("勾选重复-重复子组 书名=\(nv) 作者=\(au) 共\(S.count)本 -> 勾选\(subResult.count)个: \(subResult.sorted())")
                allResult.formUnion(subResult)
            }
        }

        // 用户自定义规则（条件-动作引擎）
        if !userRules.isEmpty {
            for row in rows {
                for ur in userRules where evaluateUserRule(row, ur) {
                    if (ur.action ?? "check") == "check" { allResult.insert(row.id) }
                    else { allResult.remove(row.id) }
                }
            }
        }

        // rule_hash 内容哈希去重（默认启用，受开关控制）
        // 仅对「已扫描内容哈希(contentHash 非空)」的文件生效：按 contentHash 全局（跨合集）分组，
        // 同哈希值内保留「最新」一个（fileDate 优先 → 回退 createdAt → 并列取最大 id）不勾选，
        // 其余（哈希相同但非最新的）强制勾选。无哈希的文件不受此规则影响，仍走其它规则。
        if enabledBuiltinKeys.contains("rule_hash") {
            let hashed = rows.filter { !$0.contentHash.isEmpty }
            let groups = Dictionary(grouping: hashed) { $0.contentHash }.filter { $0.value.count >= 2 }
            if !groups.isEmpty {
                var hashProtect = Set<Int64>()
                var hashForce = Set<Int64>()
                for (_, group) in groups {
                    let newest = group.max(by: { (a, b) -> Bool in
                        let da = a.fileDate > 0 ? a.fileDate : a.createdAt
                        let db = b.fileDate > 0 ? b.fileDate : b.createdAt
                        if da != db { return da < db }
                        return a.id < b.id
                    }) ?? group.first!
                    hashProtect.insert(newest.id)
                    for f in group where f.id != newest.id { hashForce.insert(f.id) }
                }
                // 最新的受保护（即使被其它规则勾选也还原），非最新的强制勾选（即使被保护也勾选）
                allResult = allResult.subtracting(hashProtect).union(hashForce)
                detailLines.append("勾选重复-内容哈希去重 命中\(groups.count)组 勾选\(hashForce.count)个 (最新\(hashProtect) 受保护)")
            }
        }

        return (allResult, detailLines)
    }
}
