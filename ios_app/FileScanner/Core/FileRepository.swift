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
        // 先清空本文库全部勾选，再标记本次命中的待删项，保证「重新计算」幂等、不留陈旧勾选。
        db.resetChecked(runId: runId)
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
}
