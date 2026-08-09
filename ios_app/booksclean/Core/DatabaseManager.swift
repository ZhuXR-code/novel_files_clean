import Foundation
import SQLite3

/// 本地 SQLite 数据库（对齐 Android Room：scanned_file / scan_config / scan_run / keyword_replace_rules / dup_rule_configs / operation_log）。
/// iOS 沙盒内数据库位于 Documents/file_scanner.db，使用系统内置 sqlite3。
final class DatabaseManager {
    static let shared = DatabaseManager()
    private var db: OpaquePointer?
    private let lock = NSLock()
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init() { open() }

    private func dbPath() -> String {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("file_scanner.db").path
    }

    func open() {
        if db != nil { return }
        if sqlite3_open(dbPath(), &db) != SQLITE_OK {
            LogUtil.e("DB", "无法打开数据库")
            return
        }
        createTables()
        migrateSchema()
        seedDefaultData()
    }

    // MARK: - 表结构补齐（对齐安卓 Room 迁移：升级用户旧库可能缺少新列）
    private func migrateSchema() {
        addColumnIfMissing("dup_rule_configs", "is_builtin", "INTEGER NOT NULL DEFAULT 1")
        addColumnIfMissing("dup_rule_configs", "conditions", "TEXT")
        addColumnIfMissing("dup_rule_configs", "action", "TEXT")
        addColumnIfMissing("dup_rule_configs", "sort_order", "INTEGER NOT NULL DEFAULT 0")
        addColumnIfMissing("dup_rule_configs", "created_at", "INTEGER NOT NULL DEFAULT 0")
        addColumnIfMissing("dup_rule_configs", "updated_at", "INTEGER NOT NULL DEFAULT 0")
        addColumnIfMissing("scan_config", "excluded_titles", "TEXT NOT NULL DEFAULT ''")
        addColumnIfMissing("scan_config", "excluded_title_keywords", "TEXT NOT NULL DEFAULT ''")
    }

    private func addColumnIfMissing(_ table: String, _ column: String, _ definition: String) {
        let cols = fetchAll("PRAGMA table_info(\(table))").compactMap { $0[1] as? String }
        if !cols.contains(column) {
            _ = execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
            LogUtil.i("DB", "补齐列 \(table).\(column)")
        }
    }

    // MARK: - 建表
    private func createTables() {
        let stmts = [
            """
            CREATE TABLE IF NOT EXISTS scanned_file (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              path TEXT NOT NULL,
              file_name TEXT NOT NULL,
              file_size INTEGER NOT NULL DEFAULT 0,
              title TEXT NOT NULL DEFAULT '',
              author TEXT NOT NULL DEFAULT '',
              progress TEXT NOT NULL DEFAULT '',
              source TEXT NOT NULL DEFAULT '',
              encoding TEXT NOT NULL DEFAULT '',
              title_pinyin TEXT NOT NULL DEFAULT '',
              author_pinyin TEXT NOT NULL DEFAULT '',
              content_hash TEXT NOT NULL DEFAULT '',
              ext TEXT NOT NULL DEFAULT '',
              marked INTEGER NOT NULL DEFAULT 0,
              checked INTEGER NOT NULL DEFAULT 0,
              scan_run_id INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL DEFAULT 0,
              file_date INTEGER
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_sf_run ON scanned_file(scan_run_id);",
            "CREATE INDEX IF NOT EXISTS idx_sf_created ON scanned_file(created_at);",
            "CREATE INDEX IF NOT EXISTS idx_sf_hash ON scanned_file(content_hash);",
            // 对齐安卓：唯一约束 (path, scan_run_id)，用于合并去重（同 path 只保留一条）。
            // 建唯一索引前先清理历史重复行（同 scan_run_id 同 path 仅保留 id 最小的一条），否则唯一索引会建失败。
            "DELETE FROM scanned_file WHERE id NOT IN (SELECT MIN(id) FROM scanned_file GROUP BY path, scan_run_id);",
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_sf_path_run ON scanned_file(path, scan_run_id);",
            """
            CREATE TABLE IF NOT EXISTS scan_config (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              folder_uri TEXT NOT NULL DEFAULT '',
              folder_name TEXT NOT NULL DEFAULT '',
              file_types TEXT NOT NULL DEFAULT 'txt',
              min_size_kb INTEGER NOT NULL DEFAULT 0,
              recursive INTEGER NOT NULL DEFAULT 1,
              exact_hash INTEGER NOT NULL DEFAULT 0,
              excluded_folders TEXT NOT NULL DEFAULT '',
              scan_mode TEXT NOT NULL DEFAULT 'quick'
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS scan_run (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              folder_uri TEXT NOT NULL DEFAULT '',
              folder_name TEXT NOT NULL DEFAULT '',
              file_types TEXT NOT NULL DEFAULT 'txt',
              created_at INTEGER NOT NULL DEFAULT 0,
              file_count INTEGER NOT NULL DEFAULT 0
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS keyword_replace_rules (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              scope TEXT NOT NULL DEFAULT 'scan',
              pattern TEXT NOT NULL,
              replacement TEXT NOT NULL DEFAULT '',
              sort_order INTEGER NOT NULL DEFAULT 0,
              enabled INTEGER NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL DEFAULT 0
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS dup_rule_configs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              rule_key TEXT NOT NULL,
              rule_name TEXT NOT NULL,
              enabled INTEGER NOT NULL DEFAULT 1,
              description TEXT NOT NULL DEFAULT '',
              is_builtin INTEGER NOT NULL DEFAULT 1,
              conditions TEXT,
              action TEXT,
              sort_order INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL DEFAULT 0,
              updated_at INTEGER NOT NULL DEFAULT 0
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS operation_log (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              time INTEGER NOT NULL DEFAULT 0,
              level TEXT NOT NULL DEFAULT 'I',
              tag TEXT NOT NULL DEFAULT '',
              message TEXT NOT NULL DEFAULT ''
            );
            """
        ]
        for s in stmts { _ = execute(s) }
    }

    private func seedDefaultData() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        // 勾选重复规则：幂等补齐（对齐安卓 FileRepository.seedDefaultDupRules）。
        // 内置五则的 key / 名称 / 描述 / 启用状态与安卓保持一致；已有库仅刷新内置描述，不改动用户开关。
        let dupBuiltins: [(key: String, name: String, enabled: Int, desc: String)] = [
            ("rule1", "精确重复去重", 1, "小说名+作者+进度+文件大小完全相等的文件，保留最新一个"),
            ("rule2", "纯数字进度对比", 1, "有纯数字进度的文件中，进度最高的不勾选，其余勾选"),
            ("rule3a", "含中文进度保护", 1, "含有中文进度（如「更新至50」）的文件不勾选"),
            ("rule3b", "完结特例", 1, "同一本书若同时有『完结版』（文件名含『完结/全本』）与纯数字进度的文件：当数字进度最大的文件体积小于所有『完结字样』文件中最小的那个，说明它不完整，会勾选删除，只留下完结版。"),
            ("rule4", "最大文件不勾选", 1, "同一组内文件大小唯一最大的文件不勾选"),
            ("rule5", "完结+N番外/番外N去重", 1, "进度匹配「完结+N番外」或「完结+番外N」的组内，按番外数 N 排序，最大 N 不勾选，其余勾选"),
            ("rule_hash", "内容哈希去重", 1, "对「已扫描内容哈希」的文件，按内容哈希全局（跨合集）分组：同一哈希值内保留最新一个（不勾选），其余哈希相同但非最新的文件勾选删除。无哈希的文件不受此规则影响，仍按其它规则处理。"),
        ]
        for (i, b) in dupBuiltins.enumerated() {
            let rows = fetchAll("SELECT rule_name, description, enabled FROM dup_rule_configs WHERE rule_key = ?", [b.key])
            if rows.isEmpty {
                _ = execute("INSERT INTO dup_rule_configs (rule_key,rule_name,enabled,description,is_builtin,sort_order,created_at,updated_at) VALUES (?,?,?,?,1,?,?,?)",
                            [b.key, b.name, b.enabled, b.desc, i, now, now])
            } else if let row = rows.first,
                      let oldDesc = row[1] as? String, oldDesc != b.desc {
                // 已存在：同步安卓最新内置描述文案（不动用户开关/自定义规则）。
                _ = execute("UPDATE dup_rule_configs SET rule_name = ?, description = ?, updated_at = ? WHERE rule_key = ?",
                            [b.name, b.desc, now, b.key])
            }
        }

        // 关键词替换默认规则：幂等补齐（按 scope+pattern 判断，对齐安卓 seedDefaultKeywordRules）。
        for r in KeywordReplace.DEFAULT_KEYWORD_RULES {
            let cnt = fetchAll("SELECT COUNT(*) FROM keyword_replace_rules WHERE scope = 'scan' AND pattern = ?", [r.pattern])
            let existing = (cnt.first?.first as? Int64) ?? 0
            if existing == 0 {
                _ = execute("INSERT INTO keyword_replace_rules (scope,pattern,replacement,sort_order,enabled,created_at) VALUES ('scan',?,?,?,1,?)",
                            [r.pattern, r.replacement, r.sortOrder, now])
            }
        }
        Preferences.shared.kwSeedDone = true
    }

    // MARK: - 底层执行
    private func bind(_ stmt: OpaquePointer, _ idx: Int32, _ v: Any?) {
        if let v = v as? Int64 { sqlite3_bind_int64(stmt, idx, v) }
        else if let v = v as? Int { sqlite3_bind_int64(stmt, idx, Int64(v)) }
        else if let v = v as? String {
            // Swift String 直接桥接为 const char*，SQLITE_TRANSIENT 让 SQLite 立即拷贝
            sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
        }
        else if let v = v as? Data {
            if v.isEmpty { sqlite3_bind_zeroblob(stmt, idx, 0) }
            else { v.withUnsafeBytes { p in _ = sqlite3_bind_blob(stmt, idx, p.baseAddress, Int32(v.count), SQLITE_TRANSIENT) } }
        }
        else if let v = v as? Double { sqlite3_bind_double(stmt, idx, v) }
        else { sqlite3_bind_null(stmt, idx) }
    }

    @discardableResult
    func execute(_ sql: String, _ binds: [Any?] = []) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            LogUtil.e("DB", "prepare 失败: \(sql)")
            return false
        }
        for (i, b) in binds.enumerated() { bind(stmt!, Int32(i + 1), b) }
        let rc = sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        return rc == SQLITE_DONE || rc == SQLITE_ROW
    }

    /// 执行 INSERT 并返回自增 id。
    func executeReturnId(_ sql: String, _ binds: [Any?] = []) -> Int64 {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        for (i, b) in binds.enumerated() { bind(stmt!, Int32(i + 1), b) }
        sqlite3_step(stmt)
        let id = sqlite3_last_insert_rowid(db)
        sqlite3_finalize(stmt)
        return id
    }

    func fetchAll(_ sql: String, _ binds: [Any?] = []) -> [[Any?]] {
        lock.lock(); defer { lock.unlock() }
        var result: [[Any?]] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return result }
        for (i, b) in binds.enumerated() { bind(stmt!, Int32(i + 1), b) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [Any?] = []
            let n = sqlite3_column_count(stmt)
            for i in 0..<n {
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: row.append(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT: row.append(sqlite3_column_double(stmt, i))
                case SQLITE_TEXT:
                    if let p = sqlite3_column_text(stmt, i) { row.append(String(cString: p)) } else { row.append(nil) }
                case SQLITE_BLOB:
                    let nbytes = sqlite3_column_bytes(stmt, i)
                    if let p = sqlite3_column_blob(stmt, i) { row.append(Data(bytes: p, count: Int(nbytes))) } else { row.append(nil) }
                default: row.append(nil)
                }
            }
            result.append(row)
        }
        sqlite3_finalize(stmt)
        return result
    }

    func count(_ sql: String, _ binds: [Any?] = []) -> Int {
        guard let first = fetchAll(sql, binds).first?.first as? Int64 else { return 0 }
        return Int(first)
    }

    // MARK: - scanned_file 列序
    // 0 id,1 path,2 file_name,3 file_size,4 title,5 author,6 progress,7 source,8 encoding,
    // 9 title_pinyin,10 author_pinyin,11 content_hash,12 ext,13 marked,14 checked,15 scan_run_id,16 created_at,17 file_date
    func mapScannedFile(_ row: [Any?]) -> ScannedFile {
        var f = ScannedFile()
        f.id = (row[0] as? Int64) ?? 0
        f.path = (row[1] as? String) ?? ""
        f.fileName = (row[2] as? String) ?? ""
        f.fileSize = (row[3] as? Int64) ?? 0
        f.title = (row[4] as? String) ?? ""
        f.author = (row[5] as? String) ?? ""
        f.progress = (row[6] as? String) ?? ""
        f.source = (row[7] as? String) ?? ""
        f.encoding = (row[8] as? String) ?? ""
        f.titlePinyin = (row[9] as? String) ?? ""
        f.authorPinyin = (row[10] as? String) ?? ""
        f.contentHash = (row[11] as? String) ?? ""
        f.ext = (row[12] as? String) ?? ""
        f.marked = (row[13] as? Int64).map { Int($0) } ?? 0
        f.checked = (row[14] as? Int64).map { Int($0) } ?? 0
        f.scanRunId = (row[15] as? Int64) ?? 0
        f.createdAt = (row[16] as? Int64) ?? 0
        if let fd = row[17] as? Int64 { f.fileDate = fd }
        return f
    }

    // MARK: - scanned_file CRUD
    private let SF_COLS = "id,path,file_name,file_size,title,author,progress,source,encoding,title_pinyin,author_pinyin,content_hash,ext,marked,checked,scan_run_id,created_at,file_date"

    func insertScannedFiles(_ rows: [ScannedFile]) {
        guard !rows.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let sql = "INSERT INTO scanned_file (path,file_name,file_size,title,author,progress,source,encoding,title_pinyin,author_pinyin,content_hash,ext,marked,checked,scan_run_id,created_at,file_date) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        for r in rows {
            bind(stmt!, 1, r.path); bind(stmt!, 2, r.fileName); bind(stmt!, 3, r.fileSize)
            bind(stmt!, 4, r.title); bind(stmt!, 5, r.author); bind(stmt!, 6, r.progress)
            bind(stmt!, 7, r.source); bind(stmt!, 8, r.encoding); bind(stmt!, 9, r.titlePinyin)
            bind(stmt!, 10, r.authorPinyin); bind(stmt!, 11, r.contentHash); bind(stmt!, 12, r.ext)
            bind(stmt!, 13, r.marked); bind(stmt!, 14, r.checked); bind(stmt!, 15, r.scanRunId)
            bind(stmt!, 16, r.createdAt); bind(stmt!, 17, r.fileDate)
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        sqlite3_finalize(stmt)
    }

    /// 批量更新勾选状态。SQLite 默认 SQLITE_MAX_VARIABLE_NUMBER 仅 999，
    /// 当 id 数量较大（如「勾选重复」命中数千文件）时必须分块，否则 prepare 会失败导致清理中断。
    /// 重置某文库全部勾选状态。重新计算「勾选重复」前必须先清空，否则上一次标记的待删项会残留。
    func resetChecked(runId: Int64) {
        execute("UPDATE scanned_file SET checked=0 WHERE scan_run_id=?", [runId])
    }

    func updateChecked(ids: [Int64], checked: Int) {
        guard !ids.isEmpty else { return }
        let chunkSize = 500
        for start in stride(from: 0, to: ids.count, by: chunkSize) {
            let chunk = Array(ids[start..<min(start + chunkSize, ids.count)])
            let ph = chunk.map { _ in "?" }.joined(separator: ",")
            var params: [Any] = [checked]
            params.append(contentsOf: chunk)
            execute("UPDATE scanned_file SET checked=? WHERE id IN (\(ph))", params)
        }
    }

    func setMarked(id: Int64, marked: Int) {
        execute("UPDATE scanned_file SET marked=? WHERE id=?", [marked, id])
    }

    /// 批量更新标记状态（分块，理由同 updateChecked）。
    func updateMarked(ids: [Int64], marked: Int) {
        guard !ids.isEmpty else { return }
        let chunkSize = 500
        for start in stride(from: 0, to: ids.count, by: chunkSize) {
            let chunk = Array(ids[start..<min(start + chunkSize, ids.count)])
            let ph = chunk.map { _ in "?" }.joined(separator: ",")
            var params: [Any] = [marked]
            params.append(contentsOf: chunk)
            execute("UPDATE scanned_file SET marked=? WHERE id IN (\(ph))", params)
        }
    }

    /// 重置某文库全部标记状态。
    func resetMarked(runId: Int64) {
        execute("UPDATE scanned_file SET marked=0 WHERE scan_run_id=?", [runId])
    }

    /// 按「文件名」找出重复项（同名文件保留首个、其余返回），用于一键标记重复。
    func findDuplicateIdsByFileName(runId: Int64) -> [Int64] {
        let rows = fetchAll(
            "SELECT id, file_name FROM scanned_file WHERE scan_run_id=? ORDER BY id", [runId])
        var seen = Set<String>()
        var dup: [Int64] = []
        for r in rows {
            guard let id = r.first as? Int64 else { continue }
            let name = (r.count > 1 ? r[1] as? String : nil) ?? ""
            if name.isEmpty { continue }
            if seen.contains(name) { dup.append(id) } else { seen.insert(name) }
        }
        return dup
    }

    func setChecked(id: Int64, checked: Int) {
        execute("UPDATE scanned_file SET checked=? WHERE id=?", [checked, id])
    }

    func updateFileName(id: Int64, newName: String) {
        execute("UPDATE scanned_file SET file_name=?, title=? WHERE id=?", [newName, newName, id])
    }

    func deleteFiles(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        // 收集待删文件的 path，用于跨文库同步：同一物理文件可能出现在多个文库中，
        // 在 APP 内删除（含源文件）时需要把所有文库里记录该 path 的行一并删除。
        var allPaths: [String] = []
        var affectedRuns = Set<Int64>()
        let chunkSize = 500
        for start in stride(from: 0, to: ids.count, by: chunkSize) {
            let chunk = Array(ids[start..<min(start + chunkSize, ids.count)])
            let ph = chunk.map { _ in "?" }.joined(separator: ",")
            let rows = fetchAll("SELECT path, scan_run_id FROM scanned_file WHERE id IN (\(ph))", chunk)
            for r in rows {
                if let p = r[0] as? String { allPaths.append(p) }
                if let rid = r[1] as? Int64 { affectedRuns.insert(rid) }
            }
        }
        // 按 path 删除所有文库中的匹配行
        let pathChunks = stride(from: 0, to: allPaths.count, by: chunkSize)
        for start in pathChunks {
            let pc = Array(allPaths[start..<min(start + chunkSize, allPaths.count)])
            let ph = pc.map { _ in "?" }.joined(separator: ",")
            // 重新收集本次实际命中的 run_id（可能含其他文库），以便重算计数
            let hit = fetchAll("SELECT DISTINCT scan_run_id FROM scanned_file WHERE path IN (\(ph))", pc)
            for r in hit { if let rid = r[0] as? Int64 { affectedRuns.insert(rid) } }
            execute("DELETE FROM scanned_file WHERE path IN (\(ph))", pc)
        }
        // 重算所有受影响文库的计数（file_count = 该文库剩余文件数）
        for rid in affectedRuns {
            execute("UPDATE scan_run SET file_count = (SELECT COUNT(*) FROM scanned_file WHERE scan_run_id = ?) WHERE id = ?", [rid, rid])
        }
    }

    /// 按 id 批量取文件（一次取全量会退化为逐条查询，删除大批量时极慢）。同样分块以防超变量上限。
    func getByIds(_ ids: [Int64]) -> [ScannedFile] {
        guard !ids.isEmpty else { return [] }
        var result: [ScannedFile] = []
        let chunkSize = 500
        for start in stride(from: 0, to: ids.count, by: chunkSize) {
            let chunk = Array(ids[start..<min(start + chunkSize, ids.count)])
            let ph = chunk.map { _ in "?" }.joined(separator: ",")
            let rows = fetchAll("SELECT \(SF_COLS) FROM scanned_file WHERE id IN (\(ph))", chunk)
            result.append(contentsOf: rows.map(mapScannedFile))
        }
        return result
    }

    /// 按 id 汇总文件大小（供删除确认页展示）。分块以防超变量上限。
    func sumFileSizes(ids: [Int64]) -> Int64 {
        guard !ids.isEmpty else { return 0 }
        var total: Int64 = 0
        let chunkSize = 500
        for start in stride(from: 0, to: ids.count, by: chunkSize) {
            let chunk = Array(ids[start..<min(start + chunkSize, ids.count)])
            let ph = chunk.map { _ in "?" }.joined(separator: ",")
            total += fetchAll("SELECT SUM(file_size) FROM scanned_file WHERE id IN (\(ph))", chunk)
                .first?.first as? Int64 ?? 0
        }
        return total
    }

    func getById(_ id: Int64) -> ScannedFile? {
        fetchAll("SELECT \(SF_COLS) FROM scanned_file WHERE id=?", [id]).first.map(mapScannedFile)
    }

    func countByRun(_ runId: Int64) -> Int {
        count("SELECT COUNT(*) FROM scanned_file WHERE scan_run_id=?", [runId])
    }

    /// 统计某文库内已标记（marked=1）的文件数，供首页统计卡片对齐安卓。
    func countMarked(runId: Int64) -> Int {
        count("SELECT COUNT(*) FROM scanned_file WHERE scan_run_id=? AND marked=1", [runId])
    }

    /// 分页查询（对齐 Android `getScannedFilesPaged`）。
    func getScannedFilesPaged(runId: Int64, offset: Int, limit: Int, sortBy: String, ascending: Bool,
                              titleFilter: String?, authorFilter: String?, progressFilter: String?,
                              sourceFilter: String?, search: String?,
                              checkedFilter: Int = -1, markedFilter: Int = -1,
                              checkedSortToFront: Bool = false, markedSortToFront: Bool = false) -> [ScannedFile] {
        var whereClauses = ["scan_run_id=?"]
        var binds: [Any?] = [runId]
        if let t = titleFilter, !t.isEmpty { whereClauses.append("title LIKE ?"); binds.append("\(t)%") }
        if let a = authorFilter, !a.isEmpty { whereClauses.append("author LIKE ?"); binds.append("\(a)%") }
        if let p = progressFilter, !p.isEmpty { whereClauses.append("progress LIKE ?"); binds.append("\(p)%") }
        if let s = sourceFilter, !s.isEmpty { whereClauses.append("source LIKE ?"); binds.append("\(s)%") }
        if let q = search, !q.isEmpty { whereClauses.append("(file_name LIKE ? OR title LIKE ? OR author LIKE ?)"); binds.append("%\(q)%"); binds.append("%\(q)%"); binds.append("%\(q)%") }
        if checkedFilter >= 0 { whereClauses.append("checked=?"); binds.append(checkedFilter) }
        if markedFilter >= 0 { whereClauses.append("marked=?"); binds.append(markedFilter) }
        let orderCol = sortBy == "file_name" || sortBy == "title" || sortBy == "author" || sortBy == "progress" || sortBy == "source" || sortBy == "file_size" ? sortBy : "created_at"
        let dir = ascending ? "ASC" : "DESC"
        // 置顶前缀（对齐安卓 filesPageFlow 的 checkedPrefix / markedPrefix）：
        // marked DESC 让「已标记重复文件名」的文件排在最前，checked DESC 让已勾选文件紧随其后，
        // 两者可叠加。仅在用户开启对应偏好时追加。
        var prefix = ""
        if markedSortToFront { prefix += "marked DESC, " }
        if checkedSortToFront { prefix += "checked DESC, " }
        let sql = "SELECT \(SF_COLS) FROM scanned_file WHERE \(whereClauses.joined(separator: " AND ")) ORDER BY \(prefix)\(orderCol) \(dir), id \(dir) LIMIT ? OFFSET ?"
        binds.append(limit); binds.append(offset)
        return fetchAll(sql, binds).map(mapScannedFile)
    }

    func countScannedFiles(runId: Int64, titleFilter: String?, authorFilter: String?, progressFilter: String?, sourceFilter: String?, search: String?,
                           checkedFilter: Int = -1, markedFilter: Int = -1) -> Int {
        var whereClauses = ["scan_run_id=?"]
        var binds: [Any?] = [runId]
        if let t = titleFilter, !t.isEmpty { whereClauses.append("title LIKE ?"); binds.append("\(t)%") }
        if let a = authorFilter, !a.isEmpty { whereClauses.append("author LIKE ?"); binds.append("\(a)%") }
        if let p = progressFilter, !p.isEmpty { whereClauses.append("progress LIKE ?"); binds.append("\(p)%") }
        if let s = sourceFilter, !s.isEmpty { whereClauses.append("source LIKE ?"); binds.append("\(s)%") }
        if let q = search, !q.isEmpty { whereClauses.append("(file_name LIKE ? OR title LIKE ? OR author LIKE ?)"); binds.append("%\(q)%"); binds.append("%\(q)%"); binds.append("%\(q)%") }
        if checkedFilter >= 0 { whereClauses.append("checked=?"); binds.append(checkedFilter) }
        if markedFilter >= 0 { whereClauses.append("marked=?"); binds.append(markedFilter) }
        return count("SELECT COUNT(*) FROM scanned_file WHERE \(whereClauses.joined(separator: " AND "))", binds)
    }

    /// 合集分组（对齐安卓：仅按书名 title 分组，不叠加 author）。
    func getNovelGroups(runId: Int64, minCount: Int, maxCount: Int, excludeNames: [String]) -> [NovelGroup] {
        var sql = "SELECT title, COUNT(*) AS c, SUM(file_size) AS s, SUM(CASE WHEN checked=1 THEN 1 ELSE 0 END) AS k FROM scanned_file WHERE scan_run_id=? GROUP BY title HAVING c >= ?"
        var binds: [Any?] = [runId, minCount.coerceAtLeast(0)]
        if maxCount >= 0 { sql += " AND c <= ?"; binds.append(maxCount) }
        sql += " ORDER BY c DESC, title ASC"
        let rows = fetchAll(sql, binds)
        var groups: [NovelGroup] = []
        for r in rows {
            let title = (r[0] as? String) ?? ""
            let count = (r[1] as? Int64).map(Int.init) ?? 0
            let size = (r[2] as? Int64) ?? 0
            let checked = (r[3] as? Int64).map(Int.init) ?? 0
            if excludeNames.contains(where: { !$0.isEmpty && title.contains($0) }) { continue }
            groups.append(NovelGroup(title: title.isEmpty ? "(无书名)" : title, fileCount: count, totalSize: size, checkedCount: checked))
        }
        return groups
    }

    /// 合集（按 书名+作者 分组）总数，支持与分页一致的筛选条件，用于分页栏「共 N 项」。
    func countNovelGroups(runId: Int64, minCount: Int, maxCount: Int, excludeNames: [String],
                          checkedFilter: Int = -1, markedFilter: Int = -1) -> Int {
        var sql = "SELECT COUNT(*) FROM (SELECT title FROM scanned_file WHERE scan_run_id=?"
        var binds: [Any?] = [runId]
        if checkedFilter >= 0 { sql += " AND checked=?"; binds.append(checkedFilter) }
        if markedFilter >= 0 { sql += " AND marked=?"; binds.append(markedFilter) }
        sql += " GROUP BY title HAVING COUNT(*) >= ?"
        binds.append(minCount.coerceAtLeast(0))
        if maxCount >= 0 { sql += " AND COUNT(*) <= ?"; binds.append(maxCount) }
        for n in excludeNames where !n.isEmpty { sql += " AND title NOT LIKE ?"; binds.append("%\(n)%") }
        sql += ") t"
        return count(sql, binds)
    }

    /// 合集排序 ORDER BY 构造（对齐安卓 FileRepository.buildGroupOrderBy）。
    /// sort 取值：count_desc/count_asc/size_desc/size_asc/name_asc/name_desc/date_newest/date_oldest。
    /// 安卓用 file_count/total_size/checked_count 别名，本端聚合别名为 c/s/k，语义一一对应。
    static func buildGroupOrderBy(_ sort: String, checkedSortToFront: Bool) -> String {
        let base: String
        switch sort {
        case "count_asc":   base = "(k > 0) DESC, (title = '') ASC, c ASC, title ASC"
        case "size_desc":   base = "(k > 0) DESC, (title = '') ASC, s DESC, title ASC"
        case "size_asc":    base = "(k > 0) DESC, (title = '') ASC, s ASC, title ASC"
        case "name_asc":    base = "(title = '') ASC, (k > 0) DESC, title ASC"
        case "name_desc":   base = "(title = '') ASC, (k > 0) DESC, title DESC"
        case "date_newest": base = "(k > 0) DESC, newest_date DESC, title ASC"
        case "date_oldest": base = "(k > 0) DESC, newest_date ASC, title ASC"
        default:            base = "(k > 0) DESC, (title = '') ASC, c DESC, title ASC"
        }
        guard checkedSortToFront else {
            return base
                .replacingOccurrences(of: "(k > 0) DESC, ", with: "")
                .replacingOccurrences(of: ", (k > 0) DESC", with: "")
        }
        return base
    }

    /// 合集分页查询（对齐安卓 groupsPageFlow），排序由 groupSort + checkedSortToFront 控制。
    func getNovelGroupsPaged(runId: Int64, minCount: Int, maxCount: Int, excludeNames: [String], offset: Int, limit: Int,
                             groupSort: String = "count_desc", checkedSortToFront: Bool = false,
                             checkedFilter: Int = -1, markedFilter: Int = -1) -> [NovelGroup] {
        // date_* 排序依赖 newest_date 派生列，必须一并 SELECT，否则 ORDER BY 找不到该列
        let selectExtra = groupSort.hasPrefix("date_") ? ", MAX(created_at) AS newest_date" : ""
        var sql = "SELECT title, COUNT(*) AS c, SUM(file_size) AS s, SUM(CASE WHEN checked=1 THEN 1 ELSE 0 END) AS k\(selectExtra) FROM scanned_file WHERE scan_run_id=?"
        var binds: [Any?] = [runId]
        if checkedFilter >= 0 { sql += " AND checked=?"; binds.append(checkedFilter) }
        if markedFilter >= 0 { sql += " AND marked=?"; binds.append(markedFilter) }
        sql += " GROUP BY title HAVING c >= ?"
        binds.append(minCount.coerceAtLeast(0))
        if maxCount >= 0 { sql += " AND c <= ?"; binds.append(maxCount) }
        for n in excludeNames where !n.isEmpty { sql += " AND title NOT LIKE ?"; binds.append("%\(n)%") }
        sql += " ORDER BY \(Self.buildGroupOrderBy(groupSort, checkedSortToFront: checkedSortToFront)) LIMIT ? OFFSET ?"
        binds.append(limit); binds.append(offset)
        let rows = fetchAll(sql, binds)
        var groups: [NovelGroup] = []
        for r in rows {
            let title = (r[0] as? String) ?? ""
            let count = (r[1] as? Int64).map(Int.init) ?? 0
            let size = (r[2] as? Int64) ?? 0
            let checked = (r[3] as? Int64).map(Int.init) ?? 0
            groups.append(NovelGroup(title: title.isEmpty ? "(无书名)" : title, fileCount: count, totalSize: size, checkedCount: checked))
        }
        return groups
    }

    /// 合集文件列表（对齐安卓 getFilesByTitle：仅按书名 title 取文件，不叠加 author）。
    func getGroupFiles(runId: Int64, title: String) -> [ScannedFile] {
        fetchAll("SELECT \(SF_COLS) FROM scanned_file WHERE scan_run_id=? AND title=? ORDER BY created_at DESC, id DESC", [runId, title]).map(mapScannedFile)
    }

    /// 一次性取出文库内每个 (title) 分组的「已勾选文件数」，供合集列表的三态复选框与勾选计数使用。
    /// 返回字典以 title 为键，避免合集数量多时逐组合查。
    func getGroupCheckedCounts(runId: Int64) -> [String: Int] {
        let rows = fetchAll("SELECT title, SUM(CASE WHEN checked=1 THEN 1 ELSE 0 END) AS k FROM scanned_file WHERE scan_run_id=? GROUP BY title", [runId])
        var dict: [String: Int] = [:]
        for r in rows {
            let title = (r[0] as? String) ?? ""
            let checked = (r[1] as? Int64).map(Int.init) ?? 0
            dict[title] = checked
        }
        return dict
    }

    func getDuplicateRows(runId: Int64) -> [DuplicateRow] {
        fetchAll("SELECT id,file_name,title,author,progress,source,file_size,created_at,COALESCE(file_date,0),COALESCE(content_hash,'') FROM scanned_file WHERE scan_run_id=?", [runId]).map { r in
            DuplicateRow(id: (r[0] as? Int64) ?? 0, fileName: (r[1] as? String) ?? "", title: (r[2] as? String) ?? "",
                        author: (r[3] as? String) ?? "", progress: (r[4] as? String) ?? "", source: (r[5] as? String) ?? "",
                        fileSize: (r[6] as? Int64) ?? 0, createdAt: (r[7] as? Int64) ?? 0, fileDate: (r[8] as? Int64) ?? 0,
                        contentHash: (r[9] as? String) ?? "")
        }
    }

    /// 分批取全部文件详情（用于勾选重复的内存分组计算），避免一次性 SELECT 20w 行。
    func getDuplicateRowsPaged(runId: Int64, offset: Int, limit: Int) -> [DuplicateRow] {
        fetchAll("SELECT id,file_name,title,author,progress,source,file_size,created_at,COALESCE(file_date,0),COALESCE(content_hash,'') FROM scanned_file WHERE scan_run_id=? ORDER BY id LIMIT ? OFFSET ?",
                 [runId, limit, offset]).map { r in
            DuplicateRow(id: (r[0] as? Int64) ?? 0, fileName: (r[1] as? String) ?? "", title: (r[2] as? String) ?? "",
                        author: (r[3] as? String) ?? "", progress: (r[4] as? String) ?? "", source: (r[5] as? String) ?? "",
                        fileSize: (r[6] as? Int64) ?? 0, createdAt: (r[7] as? Int64) ?? 0, fileDate: (r[8] as? Int64) ?? 0,
                        contentHash: (r[9] as? String) ?? "")
        }
    }

    /// 分批取全部文件详情（供同名重复等需要全量数据的场景），避免一次性 SELECT 20w 行。
    func getAllRowsPaged(runId: Int64, offset: Int, limit: Int) -> [DuplicateRow] {
        getDuplicateRowsPaged(runId: runId, offset: offset, limit: limit)
    }

    // MARK: - 分批勾选重复（20w+ 量级防 OOM）
    /// 分批取「已勾选」文件 id，避免一次性 SELECT 巨量行导致内存峰值。
    func getCheckedIdsBatched(runId: Int64, chunkSize: Int = 5000) -> [Int64] {
        var result: [Int64] = []
        var offset = 0
        while true {
            let rows = fetchAll(
                "SELECT id FROM scanned_file WHERE scan_run_id=? AND checked=1 ORDER BY id LIMIT ? OFFSET ?",
                [runId, chunkSize, offset])
            if rows.isEmpty { break }
            for r in rows { if let id = r.first as? Int64 { result.append(id) } }
            if rows.count < chunkSize { break }
            offset += chunkSize
        }
        return result
    }

    /// 取「已勾选」文件完整详情（用于待删清单展示）。
    func getCheckedFiles(runId: Int64) -> [ScannedFile] {
        let rows = fetchAll(
            "SELECT \(SF_COLS) FROM scanned_file WHERE scan_run_id=? AND checked=1 ORDER BY title,author,id",
            [runId])
        return rows.map { mapScannedFile($0) }
    }

    /// 文库文件总数。
    func countFiles(runId: Int64) -> Int {
        Int(count("SELECT COUNT(*) FROM scanned_file WHERE scan_run_id=?", [runId]))
    }

    // MARK: - 按「书名 + 作者」相同标记重复（对齐安卓 markDuplicatesByNameSql）
    /// 同 (title, author) 组内文件数 >= 2 时，保留 id 最小的一条，其余 marked 置 1。
    /// title 为空的文件不参与（避免空书名互相标记）。返回实际标记的文件数。
    func markDuplicatesByName(runId: Int64) -> Int {
        let sql = """
            UPDATE scanned_file SET marked = 1
            WHERE scan_run_id = ?
              AND title != ''
              AND (lower(trim(title)) || '|' || lower(trim(COALESCE(author, '')))) IN (
                  SELECT lower(trim(title)) || '|' || lower(trim(COALESCE(author, '')))
                  FROM scanned_file WHERE scan_run_id = ? AND title != ''
                  GROUP BY lower(trim(title)) || '|' || lower(trim(COALESCE(author, '')))
                  HAVING COUNT(*) > 1
              )
              AND id NOT IN (
                  SELECT MIN(id) FROM scanned_file WHERE scan_run_id = ? AND title != ''
                  GROUP BY lower(trim(title)) || '|' || lower(trim(COALESCE(author, '')))
              )
        """
        let before = countMarked(runId: runId)
        execute(sql, [runId, runId, runId])
        let after = countMarked(runId: runId)
        return max(after - before, 0)
    }

    // MARK: - 按「内容哈希相同、修改时间更早」标记/勾选重复（对齐安卓 markDuplicatesByHashSql / checkDuplicatesByHashSql）
    /// 同一 content_hash 组内仅保留「最新修改时间」的那一条（file_date 优先，回退 created_at，相同则取最大 id）不标记/不勾选，
    /// 其余更早的全部 marked=1（或 checked=1）。仅作用于已扫描内容哈希（content_hash <> ''）的文件。
    /// 若该文库未扫描内容哈希（无非空 content_hash）返回 -1，由上层提示用户先开启内容哈希重新扫描。

    /// 该文库是否已扫描内容哈希（存在非空 content_hash 的文件）。
    func hasContentHash(runId: Int64) -> Int {
        count("SELECT COUNT(*) FROM scanned_file WHERE scan_run_id=? AND content_hash <> ''", [runId])
    }

    /// 标记内容哈希相同、修改时间更早的文件。返回本次标记条数（无哈希返回 -1）。
    @discardableResult
    func markDuplicatesByHash(runId: Int64) -> Int {
        guard hasContentHash(runId: runId) > 0 else { return -1 }
        let sql = """
            UPDATE scanned_file
            SET marked = 1
            WHERE scan_run_id = ?
              AND content_hash <> ''
              AND id NOT IN (
                SELECT k.id FROM (
                    SELECT content_hash,
                           MAX(COALESCE(file_date, created_at)) AS maxdate,
                           MAX(id) AS keep_id
                    FROM scanned_file
                    WHERE scan_run_id = ? AND content_hash <> ''
                    GROUP BY content_hash
                ) g
                JOIN scanned_file k
                  ON k.scan_run_id = ?
                 AND k.content_hash = g.content_hash
                 AND COALESCE(k.file_date, k.created_at) = g.maxdate
                 AND k.id = g.keep_id
              )
        """
        let before = countMarked(runId: runId)
        execute(sql, [runId, runId, runId])
        let after = countMarked(runId: runId)
        return max(after - before, 0)
    }

    /// 勾选内容哈希相同、修改时间更早的文件。逻辑同 markDuplicatesByHash，仅置 checked=1。
    @discardableResult
    func checkDuplicatesByHash(runId: Int64) -> Int {
        guard hasContentHash(runId: runId) > 0 else { return -1 }
        let sql = """
            UPDATE scanned_file
            SET checked = 1
            WHERE scan_run_id = ?
              AND content_hash <> ''
              AND id NOT IN (
                SELECT k.id FROM (
                    SELECT content_hash,
                           MAX(COALESCE(file_date, created_at)) AS maxdate,
                           MAX(id) AS keep_id
                    FROM scanned_file
                    WHERE scan_run_id = ? AND content_hash <> ''
                    GROUP BY content_hash
                ) g
                JOIN scanned_file k
                  ON k.scan_run_id = ?
                 AND k.content_hash = g.content_hash
                 AND COALESCE(k.file_date, k.created_at) = g.maxdate
                 AND k.id = g.keep_id
              )
        """
        let before = count("SELECT COUNT(*) FROM scanned_file WHERE scan_run_id=? AND checked=1", [runId])
        execute(sql, [runId, runId, runId])
        let after = count("SELECT COUNT(*) FROM scanned_file WHERE scan_run_id=? AND checked=1", [runId])
        return max(after - before, 0)
    }

    // MARK: - 分批按文件名找重复（20w+ 量级防 OOM）
    /// 用 SQL 子查询直接定位「同名且 >=2 个」的文件 id，分批游标返回，避免全表载入内存。
    func findDuplicateIdsByFileNameBatched(runId: Int64, chunkSize: Int = 5000) -> [Int64] {
        var result: [Int64] = []
        var offset = 0
        let dupNamesSql = "SELECT file_name FROM scanned_file WHERE scan_run_id=? GROUP BY file_name HAVING COUNT(*) >= 2"
        while true {
            let rows = fetchAll(
                "SELECT id FROM scanned_file WHERE scan_run_id=? AND file_name IN (\(dupNamesSql)) ORDER BY id LIMIT ? OFFSET ?",
                [runId, runId, chunkSize, offset])
            if rows.isEmpty { break }
            for r in rows { if let id = r.first as? Int64 { result.append(id) } }
            if rows.count < chunkSize { break }
            offset += chunkSize
        }
        return result
    }

    func getEnabledBuiltinRuleKeys() -> Set<String> {
        Set(fetchAll("SELECT rule_key FROM dup_rule_configs WHERE is_builtin=1 AND enabled=1").compactMap { $0.first as? String })
    }

    func getEnabledUserRules() -> [DupRuleConfig] {
        // 对齐安卓：自定义规则还需 conditions IS NOT NULL 才参与（空条件视为无效、不参与勾选）。
        fetchAll("SELECT id,rule_key,rule_name,enabled,description,is_builtin,conditions,action,sort_order,created_at,updated_at FROM dup_rule_configs WHERE is_builtin=0 AND enabled=1 AND conditions IS NOT NULL ORDER BY sort_order ASC").map { r in
            var c = DupRuleConfig()
            c.id = (r[0] as? Int64) ?? 0
            c.ruleKey = (r[1] as? String) ?? ""
            c.ruleName = (r[2] as? String) ?? ""
            c.enabled = (r[3] as? Int64).map { $0 != 0 } ?? false
            c.desc = (r[4] as? String) ?? ""
            c.isBuiltin = (r[5] as? Int64).map { $0 != 0 } ?? false
            c.conditions = r[6] as? String
            c.action = r[7] as? String
            c.sortOrder = (r[8] as? Int64).map(Int.init) ?? 0
            c.createdAt = (r[9] as? Int64) ?? 0
            c.updatedAt = (r[10] as? Int64) ?? 0
            return c
        }
    }

    // MARK: - scan_config
    func getScanConfigs() -> [ScanConfig] {
        fetchAll("SELECT id,name,folder_uri,folder_name,file_types,min_size_kb,recursive,exact_hash,excluded_folders,excluded_titles,excluded_title_keywords,scan_mode FROM scan_config ORDER BY id DESC").map { r in
            var c = ScanConfig()
            c.id = (r[0] as? Int64) ?? 0
            c.name = (r[1] as? String) ?? ""
            c.folderUri = (r[2] as? String) ?? ""
            c.folderName = (r[3] as? String) ?? ""
            c.fileTypes = (r[4] as? String) ?? "txt"
            c.minSizeKb = (r[5] as? Int64).map(Int.init) ?? 0
            c.recursive = (r[6] as? Int64).map { $0 != 0 } ?? true
            c.exactHash = (r[7] as? Int64).map { $0 != 0 } ?? false
            c.excludedFolders = (r[8] as? String) ?? ""
            c.excludedTitles = (r[9] as? String) ?? ""
            c.excludedTitleKeywords = (r[10] as? String) ?? ""
            c.scanMode = (r[11] as? String) ?? "quick"
            return c
        }
    }

    func getScanConfig(_ id: Int64) -> ScanConfig? {
        getScanConfigs().first { $0.id == id }
    }

    func saveScanConfig(_ c: ScanConfig) -> Int64 {
        if c.id > 0 {
            execute("UPDATE scan_config SET name=?,folder_uri=?,folder_name=?,file_types=?,min_size_kb=?,recursive=?,exact_hash=?,excluded_folders=?,excluded_titles=?,excluded_title_keywords=?,scan_mode=? WHERE id=?",
                    [c.name, c.folderUri, c.folderName, c.fileTypes, c.minSizeKb, c.recursive ? 1 : 0, c.exactHash ? 1 : 0, c.excludedFolders, c.excludedTitles, c.excludedTitleKeywords, c.scanMode, c.id])
            return c.id
        } else {
            return executeReturnId("INSERT INTO scan_config (name,folder_uri,folder_name,file_types,min_size_kb,recursive,exact_hash,excluded_folders,excluded_titles,excluded_title_keywords,scan_mode) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                                   [c.name, c.folderUri, c.folderName, c.fileTypes, c.minSizeKb, c.recursive ? 1 : 0, c.exactHash ? 1 : 0, c.excludedFolders, c.excludedTitles, c.excludedTitleKeywords, c.scanMode])
        }
    }

    func deleteScanConfig(_ id: Int64) { execute("DELETE FROM scan_config WHERE id=?", [id]) }

    // MARK: - scan_run
    func saveScanRun(_ r: ScanRun) -> Int64 {
        if r.id > 0 {
            execute("UPDATE scan_run SET name=?,folder_uri=?,folder_name=?,file_types=?,file_count=? WHERE id=?",
                    [r.name, r.folderUri, r.folderName, r.fileTypes, r.fileCount, r.id])
            return r.id
        }
        return executeReturnId("INSERT INTO scan_run (name,folder_uri,folder_name,file_types,created_at,file_count) VALUES (?,?,?,?,?,?)",
                               [r.name, r.folderUri, r.folderName, r.fileTypes, r.createdAt, r.fileCount])
    }

    func getScanRuns() -> [ScanRun] {
        fetchAll("SELECT id,name,folder_uri,folder_name,file_types,created_at,file_count FROM scan_run ORDER BY id DESC").map(mapScanRun)
    }

    private func mapScanRun(_ r: [Any?]) -> ScanRun {
        var r0 = ScanRun()
        r0.id = (r[0] as? Int64) ?? 0
        r0.name = (r[1] as? String) ?? ""
        r0.folderUri = (r[2] as? String) ?? ""
        r0.folderName = (r[3] as? String) ?? ""
        r0.fileTypes = (r[4] as? String) ?? "txt"
        r0.createdAt = (r[5] as? Int64) ?? 0
        r0.fileCount = (r[6] as? Int64).map(Int.init) ?? 0
        return r0
    }

    /// 按 id 直接查询单条扫描记录。原先每次都 getScanRuns() 全量加载再过滤，
    /// 在删除/预览等高频路径上（每个文件都触发）会反复全表查询，必须直查。
    func getScanRun(_ id: Int64) -> ScanRun? {
        fetchAll("SELECT id,name,folder_uri,folder_name,file_types,created_at,file_count FROM scan_run WHERE id=?", [id])
            .first.map(mapScanRun)
    }

    func updateScanRunFileCount(_ id: Int64, count: Int) {
        execute("UPDATE scan_run SET file_count=? WHERE id=?", [count, id])
    }

    func deleteScanRun(_ id: Int64) {
        execute("DELETE FROM scanned_file WHERE scan_run_id=?", [id])
        execute("DELETE FROM scan_run WHERE id=?", [id])
    }

    /// 合并多个文库为一个新文库（对齐安卓 ScanRunDao.mergeRuns）。
    /// 流程：① 新建文库 ② 用 INSERT...SELECT 复制源文库文件（保留 marked/checked/content_hash 等全部状态，
    /// 相同 path 靠唯一约束去重）③ 统计新文库文件数 ④ 删除源文库及其文件。
    /// 要求 sourceIds.count >= 2，否则返回 -1。
    @discardableResult
    func mergeRuns(_ sourceIds: [Int64], newName: String) -> Int64 {
        guard sourceIds.count >= 2 else { return -1 }
        let placeholders = sourceIds.map { _ in "?" }.joined(separator: ",")
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = name.isEmpty ? "合并文库" : name
        // 继承第一个源文库的安全作用域书签（folder_uri），否则合并后预览/删除/打开等操作均无法访问文件
        let firstSource = getScanRun(sourceIds[0])
        let mergedFolderUri = firstSource?.folderUri ?? ""
        // 合并库使用新名称作为 folder_name，避免列表优先显示 folder_name 时回退成某个源文库原名
        execute("BEGIN TRANSACTION", [])
        let newId = executeReturnId("INSERT INTO scan_run (name, folder_uri, folder_name, created_at, file_count) VALUES (?, ?, ?, ?, 0)",
                                    [finalName, mergedFolderUri, finalName, Int64(Date().timeIntervalSince1970 * 1000)])
        guard newId > 0 else {
            execute("ROLLBACK", [])
            LogUtil.e("DB", "合并文库失败: 插入新文库记录失败 name=\(finalName)")
            return -1
        }
        let copyBind: [Any?] = [Int64(newId)] + sourceIds.map { $0 as Any? }
        let ok = execute(
            "INSERT INTO scanned_file (scan_run_id, path, file_name, file_size, title, author, progress, source, encoding, title_pinyin, author_pinyin, content_hash, ext, marked, checked, created_at, file_date) " +
            "SELECT ?, path, file_name, file_size, title, author, progress, source, encoding, title_pinyin, author_pinyin, content_hash, ext, marked, checked, created_at, file_date " +
            "FROM scanned_file WHERE scan_run_id IN (\(placeholders)) " +
            "ON CONFLICT(path, scan_run_id) DO NOTHING",
            copyBind
        )
        guard ok else {
            execute("ROLLBACK", [])
            LogUtil.e("DB", "合并文库失败: 复制源文库文件到新文库失败 newId=\(newId) 源=\(sourceIds.map(String.init).joined(separator: ","))")
            return -1
        }
        let cntRows = fetchAll("SELECT COUNT(*) FROM scanned_file WHERE scan_run_id = ?", [Int64(newId)])
        let fileCount = (cntRows.first?.first as? Int64).map { Int($0) } ?? 0
        execute("UPDATE scan_run SET file_count = ? WHERE id = ?", [fileCount, Int64(newId)])
        // 保留原文库：仅新增一个合并库，不删除被合并的源文库
        execute("COMMIT", [])
        return newId
    }

    // MARK: - keyword_replace_rules
    func getKeywordReplaceRules(scope: String? = nil) -> [KeywordReplaceRule] {
        let rows: [[Any?]]
        if let s = scope {
            rows = fetchAll("SELECT id,scope,pattern,replacement,sort_order,enabled,created_at FROM keyword_replace_rules WHERE scope=? ORDER BY sort_order ASC, id ASC", [s])
        } else {
            rows = fetchAll("SELECT id,scope,pattern,replacement,sort_order,enabled,created_at FROM keyword_replace_rules ORDER BY sort_order ASC, id ASC")
        }
        return rows.map { r in
            var k = KeywordReplaceRule()
            k.id = (r[0] as? Int64) ?? 0
            k.scope = (r[1] as? String) ?? "scan"
            k.pattern = (r[2] as? String) ?? ""
            k.replacement = (r[3] as? String) ?? ""
            k.sortOrder = (r[4] as? Int64).map(Int.init) ?? 0
            k.enabled = (r[5] as? Int64).map { $0 != 0 } ?? true
            k.createdAt = (r[6] as? Int64) ?? 0
            return k
        }
    }

    func saveKeywordReplaceRule(_ k: KeywordReplaceRule) -> Int64 {
        executeReturnId("INSERT INTO keyword_replace_rules (scope,pattern,replacement,sort_order,enabled,created_at) VALUES (?,?,?,?,?,?)",
                        [k.scope, k.pattern, k.replacement, k.sortOrder, k.enabled ? 1 : 0, k.createdAt])
    }

    func updateKeywordReplaceRule(_ k: KeywordReplaceRule) {
        execute("UPDATE keyword_replace_rules SET scope=?,pattern=?,replacement=?,sort_order=?,enabled=? WHERE id=?",
                [k.scope, k.pattern, k.replacement, k.sortOrder, k.enabled ? 1 : 0, k.id])
    }

    func deleteKeywordReplaceRule(_ id: Int64) { execute("DELETE FROM keyword_replace_rules WHERE id=?", [id]) }

    /// 批量启用 / 停用关键词替换规则（供「批量启用 / 批量不启用」按当前搜索结果操作）。
    /// 分批 900 条执行，规避 SQLite 变量数上限；写库后返回上一页再进入状态依旧保留。
    @discardableResult
    func setKeywordRulesEnabled(ids: [Int64], enabled: Bool) -> Int {
        guard !ids.isEmpty else { return 0 }
        var done = 0
        var idx = 0
        while idx < ids.count {
            let chunk = Array(ids[idx..<min(idx + 900, ids.count)])
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            var args: [Any?] = [enabled ? 1 : 0]
            args.append(contentsOf: chunk.map { $0 as Any? })
            execute("UPDATE keyword_replace_rules SET enabled=? WHERE id IN (\(placeholders))", args)
            done += chunk.count
            idx += 900
        }
        return done
    }

    // MARK: - dup_rule_configs
    func getDupRuleConfigs() -> [DupRuleConfig] {
        fetchAll("SELECT id,rule_key,rule_name,enabled,description,is_builtin,conditions,action,sort_order,created_at,updated_at FROM dup_rule_configs ORDER BY is_builtin DESC, sort_order ASC").map { r in
            var c = DupRuleConfig()
            c.id = (r[0] as? Int64) ?? 0
            c.ruleKey = (r[1] as? String) ?? ""
            c.ruleName = (r[2] as? String) ?? ""
            c.enabled = (r[3] as? Int64).map { $0 != 0 } ?? false
            c.desc = (r[4] as? String) ?? ""
            c.isBuiltin = (r[5] as? Int64).map { $0 != 0 } ?? false
            c.conditions = r[6] as? String
            c.action = r[7] as? String
            c.sortOrder = (r[8] as? Int64).map(Int.init) ?? 0
            c.createdAt = (r[9] as? Int64) ?? 0
            c.updatedAt = (r[10] as? Int64) ?? 0
            return c
        }
    }

    func saveDupRuleConfig(_ c: DupRuleConfig) -> Int64 {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if c.id > 0 {
            execute("UPDATE dup_rule_configs SET rule_key=?,rule_name=?,enabled=?,description=?,conditions=?,action=?,updated_at=? WHERE id=?",
                    [c.ruleKey, c.ruleName, c.enabled ? 1 : 0, c.desc, c.conditions ?? NSNull(), c.action ?? NSNull(), now, c.id])
            return c.id
        }
        return executeReturnId("INSERT INTO dup_rule_configs (rule_key,rule_name,enabled,description,is_builtin,conditions,action,sort_order,created_at,updated_at) VALUES (?,?,?,?,0,?,?,?,?,?)",
                               [c.ruleKey, c.ruleName, c.enabled ? 1 : 0, c.desc, c.conditions ?? NSNull(), c.action ?? NSNull(), c.sortOrder, now, now])
    }

    func setDupRuleEnabled(key: String, enabled: Bool) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        execute("UPDATE dup_rule_configs SET enabled=?, updated_at=? WHERE rule_key=?", [enabled ? 1 : 0, now, key])
    }

    // MARK: - operation_log
    func logOperation(level: String, tag: String, message: String) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        execute("INSERT INTO operation_log (time,level,tag,message) VALUES (?,?,?,?)", [now, level, tag, message])
    }

    func getOperationLogs(limit: Int = 500) -> [LogEntry] {
        fetchAll("SELECT id,time,level,tag,message FROM operation_log ORDER BY id DESC LIMIT ?", [limit]).map { r in
            var e = LogEntry()
            e.id = (r[0] as? Int64) ?? 0
            e.time = (r[1] as? Int64) ?? 0
            e.level = (r[2] as? String) ?? ""
            e.tag = (r[3] as? String) ?? ""
            e.message = (r[4] as? String) ?? ""
            return e
        }
    }

    func clearOperationLogs() { execute("DELETE FROM operation_log") }

    // MARK: - 导出 / 清空（对齐安卓「导出已标记」「清空数据」）
    /// 返回全部已标记（marked=1）文件，供导出清单使用。
    func getAllMarked() -> [ScannedFile] {
        fetchAll("SELECT \(SF_COLS) FROM scanned_file WHERE marked=1 ORDER BY scan_run_id, id").map(mapScannedFile)
    }

    /// 清空全部本地数据（扫描记录、文件、日志、配置）。
    func deleteAllData() {
        execute("DELETE FROM scanned_file")
        execute("DELETE FROM scan_run")
        execute("DELETE FROM operation_log")
        execute("DELETE FROM scan_config")
        execute("DELETE FROM keyword_replace_rules")
        execute("DELETE FROM dup_rule_configs")
    }
}

extension Int {
    func coerceAtLeast(_ min: Int) -> Int { Swift.max(self, min) }
    func clamped(to range: ClosedRange<Int>) -> Int { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}
