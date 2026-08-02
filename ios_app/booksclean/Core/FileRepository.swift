import Foundation

/// 勾选重复分组明细（供「一键清理」确认页展示）。
struct DuplicateDetail: Identifiable {
    var id: String { groupKey }
    var groupKey: String
    var title: String
    var author: String
    var fileCount: Int
    var dupCount: Int
    var totalSize: Int64
}

/// 高层仓储逻辑（对齐 Android `FileRepository`，委托 DatabaseManager + DupRuleLogic）。
final class FileRepository {
    static let shared = FileRepository()
    private let db = DatabaseManager.shared

    // MARK: - 文库
    func createScanRun(name: String, folderUri: String, folderName: String, fileTypes: String) -> Int64 {
        db.saveScanRun(ScanRun(name: name, folderUri: folderUri, folderName: folderName, fileTypes: fileTypes, createdAt: Int64(Date().timeIntervalSince1970 * 1000)))
    }
    func setRunFileCount(runId: Int64, count: Int) { db.updateScanRunFileCount(runId, count: count) }
    func deleteScanRun(runId: Int64) {
        db.deleteScanRun(runId)
        LogUtil.i("Repo", "删除文库 run=\(runId)")
    }
    func getScanRuns() -> [ScanRun] { db.getScanRuns() }
    func getScanRun(_ id: Int64) -> ScanRun? { db.getScanRun(id) }
    /// 统计文库内已标记文件数（首页统计卡片）。
    func countMarkedFiles(runId: Int64) -> Int { db.countMarked(runId: runId) }

    // MARK: - 文件
    func insertAll(_ files: [ScannedFile]) { db.insertScannedFiles(files) }
    func getById(_ id: Int64) -> ScannedFile? { db.getById(id) }
    func getByIds(_ ids: [Int64]) -> [ScannedFile] { db.getByIds(ids) }
    func setChecked(id: Int64, checked: Bool) { db.setChecked(id: id, checked: checked ? 1 : 0) }
    func updateChecked(ids: [Int64], checked: Bool) { db.updateChecked(ids: ids, checked: checked ? 1 : 0) }
    func resetChecked(runId: Int64) { db.resetChecked(runId: runId) }
    func setMarked(id: Int64, marked: Bool) { db.setMarked(id: id, marked: marked ? 1 : 0) }
    func updateMarked(ids: [Int64], marked: Bool) { db.updateMarked(ids: ids, marked: marked ? 1 : 0) }
    func resetMarked(runId: Int64) { db.resetMarked(runId: runId) }

    /// 一键标记同名重复文件（保留首个），返回标记条数。对齐安卓「标记重复文件名」。
    @discardableResult
    func markDuplicatesByFileName(runId: Int64) -> Int {
        let ids = db.findDuplicateIdsByFileNameBatched(runId: runId)
        db.updateMarked(ids: ids, marked: 1)
        LogUtil.i("Repo", "按文件名标记重复 \(ids.count) 条")
        return ids.count
    }
    func updateFileName(id: Int64, newName: String) { db.updateFileName(id: id, newName: newName) }
    func deleteFiles(ids: [Int64]) { db.deleteFiles(ids: ids) }

    // MARK: - 关键词替换规则
    func getEnabledRules(scope: String) -> [KeywordReplaceRule] {
        db.getKeywordReplaceRules(scope: scope).filter { $0.enabled }
    }

    // MARK: - 勾选重复
    /// 复刻 PC 端「勾选重复」逻辑，仅计算应勾选（待删）的 id，并写入 checked=1。
    /// 20w+ 量级优化：分批游标（每批 5000 行）取详情，内存中按 (author,title) 分组并计算，
    /// 内存峰值 = 单批大小（5000 行），远小于全量 20w 行，避免 iPhone OOM / 卡死。
    @discardableResult
    func selectDuplicateIds(runId: Int64, exactHash: Bool = false) -> Set<Int64> {
        let enabled = db.getEnabledBuiltinRuleKeys()
        let userRules = db.getEnabledUserRules()
        var result = Set<Int64>()
        var detailCount = 0
        var sampleLines: [String] = []
        let batch = 5000
        var offset = 0
        while true {
            let rows = db.getDuplicateRowsPaged(runId: runId, offset: offset, limit: batch)
            if rows.isEmpty { break }
            let (groupResult, groupDetail) = DupRuleLogic.computeDuplicateChecks(rows, enabled, userRules)
            if !groupResult.isEmpty {
                result.formUnion(groupResult)
                detailCount += 1
                if sampleLines.count < 10 { sampleLines.append(contentsOf: groupDetail.prefix(10 - sampleLines.count)) }
            }
            if rows.count < batch { break }
            offset += batch
        }
        let sample = sampleLines.prefix(10).joined(separator: "；")
        LogUtil.i("Repo", "勾选重复 完成 run=\(runId) 规则=\(enabled) 子组=\(detailCount) 勾选=\(result.count)" + (sample.isEmpty ? "" : " 样例：\(sample)"))
        // 仅把本次命中的待删项标记为勾选，不清空其它已勾选项（对齐安卓 setCheckedForIds 的「合并勾选」语义：
        // 用户手动勾选的文件保留，重复规则命中的文件在此基础上增量叠加，避免一键清理清掉用户已有勾选）。
        if !result.isEmpty { db.updateChecked(ids: Array(result), checked: 1) }
        return result
    }

    /// 一键清理确认页所需的分组明细：同 (作者+书名) 子组内，存在待删（已勾选重复）的子组。
    /// 同样分批游标，避免全量载入 20w 行。
    func getDupDetails(runId: Int64) -> [DuplicateDetail] {
        let enabled = db.getEnabledBuiltinRuleKeys()
        let userRules = db.getEnabledUserRules()
        var details: [DuplicateDetail] = []
        let batch = 5000
        var offset = 0
        while true {
            let rows = db.getDuplicateRowsPaged(runId: runId, offset: offset, limit: batch)
            if rows.isEmpty { break }
            let (groupResult, _) = DupRuleLogic.computeDuplicateChecks(rows, enabled, userRules)
            // 仅对命中规则、含待删项的子组输出明细
            let subgroups = Dictionary(grouping: rows) { "\($0.author)\u{0000}\($0.title)" }
            for (key, S) in subgroups {
                let dupIds = S.filter { groupResult.contains($0.id) }
                if dupIds.isEmpty { continue }
                let totalSize = S.reduce(0) { $0 + $1.fileSize }
                let parts = key.split(separator: "\u{0000}", maxSplits: 1)
                let author = String(parts.first ?? "")
                let title = parts.count > 1 ? String(parts[1]) : ""
                details.append(DuplicateDetail(groupKey: key,
                                               title: title.isEmpty ? "(无书名)" : title,
                                               author: author,
                                               fileCount: S.count,
                                               dupCount: dupIds.count,
                                               totalSize: totalSize))
            }
            if rows.count < batch { break }
            offset += batch
        }
        return details.sorted { $0.fileCount > $1.fileCount }
    }

    /// 计算待删文件 id 列表（已勾选的文件），供删除流程使用。分批取，降低内存峰值。
    func getCheckedIds(runId: Int64) -> [Int64] {
        db.getCheckedIdsBatched(runId: runId)
    }

    func getCheckedCount(runId: Int64) -> Int {
        db.count("SELECT COUNT(*) FROM scanned_file WHERE scan_run_id=? AND checked=1", [runId])
    }

    /// 待删清单（已勾选文件完整详情）。
    func getCheckedFiles(runId: Int64) -> [ScannedFile] {
        db.getCheckedFiles(runId: runId)
    }

    /// 文库文件总数。
    func countFiles(runId: Int64) -> Int {
        db.countFiles(runId: runId)
    }

    /// 重复组数：已勾选文件按 (作者, 书名) 规范化分组后，组内文件数 >= 2 的组数。
    func getDuplicateGroups(runId: Int64) -> Int {
        let files = db.getCheckedFiles(runId: runId)
        var groups: [String: Int] = [:]
        for f in files {
            let key = "\(f.author.trimmingCharacters(in: .whitespaces).lowercased())\u{0000}\(f.title.trimmingCharacters(in: .whitespaces).lowercased())"
            groups[key, default: 0] += 1
        }
        return groups.values.filter { $0 >= 2 }.count
    }

    // MARK: - 关键词 / 勾选规则持久化
    func getKeywordReplaceRules(scope: String? = nil) -> [KeywordReplaceRule] { db.getKeywordReplaceRules(scope: scope) }
    @discardableResult
    func saveKeywordReplaceRule(_ r: KeywordReplaceRule) -> Int64 { db.saveKeywordReplaceRule(r) }
    func updateKeywordReplaceRule(_ r: KeywordReplaceRule) { db.updateKeywordReplaceRule(r) }
    func deleteKeywordReplaceRule(_ id: Int64) { db.deleteKeywordReplaceRule(id) }

    func getDupRuleConfigs() -> [DupRuleConfig] { db.getDupRuleConfigs() }
    @discardableResult
    func saveDupRuleConfig(_ c: DupRuleConfig) -> Int64 { db.saveDupRuleConfig(c) }
    func deleteDupRuleConfig(_ id: Int64) { db.execute("DELETE FROM dup_rule_configs WHERE id=?", [id]) }
    func setDupRuleEnabled(key: String, enabled: Bool) {
        db.setDupRuleEnabled(key: key, enabled: enabled)
        LogUtil.i("Repo", "勾选重复规则 \(key) 设为 \(enabled)")
    }

    // MARK: - 日志
    func logOperation(level: String, tag: String, message: String) { db.logOperation(level: level, tag: tag, message: message) }
    func getOperationLogs(limit: Int = 500) -> [LogEntry] { db.getOperationLogs(limit: limit) }
    func clearOperationLogs() { db.clearOperationLogs() }

    // MARK: - 扫描配置
    func getScanConfigs() -> [ScanConfig] { db.getScanConfigs() }
    func getScanConfig(_ id: Int64) -> ScanConfig? { db.getScanConfig(id) }
    func saveScanConfig(_ c: ScanConfig) -> Int64 { db.saveScanConfig(c) }
    func deleteScanConfig(_ id: Int64) { db.deleteScanConfig(id) }

    // MARK: - 导出 / 清空（对齐安卓）
    /// 导出已标记文件清单到应用 Documents 目录，返回文件路径；无标记项时返回 nil。
    func exportMarkedFiles() -> String? {
        let marked = db.getAllMarked()
        guard !marked.isEmpty else { return nil }
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd_HHmmss"
        let name = "marked_files_\(df.string(from: Date())).txt"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        var text = "已标记文件清单（共 \(marked.count) 个）\n"
        text += "生成时间：\(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))\n"
        text += String(repeating: "=", count: 40) + "\n"
        for f in marked {
            text += "[文库 \(f.scanRunId)] \(f.fileName)\n"
            if !f.title.isEmpty { text += "  书名：\(f.title)\n" }
            if !f.author.isEmpty { text += "  作者：\(f.author)\n" }
            if !f.path.isEmpty { text += "  路径：\(f.path)\n" }
            text += "\n"
        }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            LogUtil.i("Repo", "导出已标记 \(marked.count) 个 -> \(url.path)")
            return url.path
        } catch {
            LogUtil.e("Repo", "导出已标记失败：\(error.localizedDescription)")
            return nil
        }
    }

    /// 清空全部本地数据（对齐安卓「清空数据」）。
    func clearAllData() {
        db.deleteAllData()
        LogUtil.i("Repo", "已清空全部本地数据")
    }

    /// 导出指定文库的文件清单到应用 Documents 目录，返回文件路径；
    /// 无文件时返回 nil。对齐安卓文库「导出列表」功能。
    /// 清单中的路径以人类可读形式展示（仅展示用，不改变底层存储）。
    func exportLibrary(runId: Int64) -> String? {
        let files = db.getScannedFilesPaged(runId: runId, offset: 0, limit: Int.max,
                                            sortBy: "created_at", ascending: true,
                                            titleFilter: nil, authorFilter: nil,
                                            progressFilter: nil, sourceFilter: nil, search: nil)
        guard !files.isEmpty else { return nil }
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd_HHmmss"
        let name = "library_files_\(runId)_\(df.string(from: Date())).txt"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        var text = "文库文件清单（共 \(files.count) 个）\n"
        text += "生成时间：\(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))\n"
        text += String(repeating: "=", count: 40) + "\n"
        for f in files {
            text += "\(f.fileName)\n"
            if !f.title.isEmpty { text += "  书名：\(f.title)\n" }
            if !f.author.isEmpty { text += "  作者：\(f.author)\n" }
            if !f.path.isEmpty { text += "  路径：\(FormatUtil.toHumanReadablePath(f.path))\n" }
            text += "\n"
        }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            LogUtil.i("Repo", "导出文库 \(runId) \(files.count) 个 -> \(url.path)")
            return url.path
        } catch {
            LogUtil.e("Repo", "导出文库失败：\(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 合集勾选计数（三态复选框）
    func getGroupCheckedCounts(runId: Int64) -> [String: Int] {
        db.getGroupCheckedCounts(runId: runId)
    }

    // MARK: - 导出列表清单（对齐安卓 ListExportUtil 的列选择 / 本页·全部）
    /// columns: 要导出的列集合，可选值：
    /// "name"(文件名) "title"(书名) "author"(作者) "size"(大小) "path"(路径)
    /// "date"(日期) "extra"(其他) "checked"(勾选状态) "marked"(标记状态)
    /// all: true 导出全部文件；false 仅导出当前页（由 offset/limit 限定）。
    func exportLibraryText(runId: Int64, columns: Set<String>, all: Bool,
                           offset: Int = 0, limit: Int = Int.max) -> String? {
        let files: [ScannedFile]
        if all {
            files = db.getScannedFilesPaged(runId: runId, offset: 0, limit: Int.max,
                                            sortBy: "created_at", ascending: true,
                                            titleFilter: nil, authorFilter: nil,
                                            progressFilter: nil, sourceFilter: nil, search: nil)
        } else {
            files = db.getScannedFilesPaged(runId: runId, offset: offset, limit: limit,
                                            sortBy: "created_at", ascending: true,
                                            titleFilter: nil, authorFilter: nil,
                                            progressFilter: nil, sourceFilter: nil, search: nil)
        }
        guard !files.isEmpty else { return nil }

        // 列顺序固定，保证与安卓一致
        let ordered = ["name", "title", "author", "size", "path", "date", "extra", "checked", "marked"]
        let chosen = ordered.filter { columns.contains($0) }
        let headers = chosen.map { Self.columnLabel($0) }

        var text = "文库文件清单（共 \(files.count) 个"
        text += (columns.isEmpty ? "，默认全字段" : "，导出列：\(headers.joined(separator: " | "))")
        text += "）\n"
        text += "生成时间：\(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))\n"
        text += String(repeating: "=", count: 40) + "\n"

        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        for f in files {
            var parts: [String] = []
            for col in chosen {
                switch col {
                case "name":   parts.append(f.fileName)
                case "title":  parts.append(f.title.isEmpty ? "" : f.title)
                case "author": parts.append(f.author.isEmpty ? "" : f.author)
                case "size":   parts.append(FormatUtil.formatSize(f.fileSize))
                case "path":   parts.append(f.path.isEmpty ? "" : FormatUtil.toHumanReadablePath(f.path))
                case "date":   parts.append(f.fileDate.map { df.string(from: Date(timeIntervalSince1970: TimeInterval($0) / 1000)) } ?? "")
                case "extra":  parts.append("\(f.progress.isEmpty ? "" : "进度:\(f.progress) ")\(f.source.isEmpty ? "" : "来源:\(f.source)")")
                case "checked":parts.append(f.checked == 1 ? "已勾选" : "")
                case "marked": parts.append(f.marked == 1 ? "已标记" : "")
                default: break
                }
            }
            text += parts.joined(separator: " | ") + "\n"
        }
        let name = "library_export_\(runId)_"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(name).txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            LogUtil.i("Repo", "导出列表 \(files.count) 个 -> \(url.path)")
            return url.path
        } catch {
            LogUtil.e("Repo", "导出列表失败：\(error.localizedDescription)")
            return nil
        }
    }

    private static func columnLabel(_ col: String) -> String {
        switch col {
        case "name":   return "文件名"
        case "title":  return "书名"
        case "author": return "作者"
        case "size":   return "大小"
        case "path":   return "路径"
        case "date":   return "日期"
        case "extra":  return "其他"
        case "checked":return "勾选状态"
        case "marked": return "标记状态"
        default:       return col
        }
    }
}
