import Foundation

/// 扫描得到的单个文件（对应 Android `ScannedFileEntity` / PC `scanned_file` 表）。
/// 标记 `Sendable`：预览等场景需把它传入后台 `Task.detached` 做文件读取/解码，
/// 全部成员均为值类型，跨并发域传递安全。
struct ScannedFile: Identifiable, Sendable {
    var id: Int64 = 0
    var path: String = ""
    var fileName: String = ""
    var fileSize: Int64 = 0
    var title: String = ""
    var author: String = ""
    var progress: String = ""
    var source: String = ""
    var encoding: String = ""
    var titlePinyin: String = ""
    var authorPinyin: String = ""
    var contentHash: String = ""
    var ext: String = ""
    var marked: Int = 0
    var checked: Int = 0
    var scanRunId: Int64 = 0
    var createdAt: Int64 = 0
    var fileDate: Int64? = nil
}

/// 扫描配置（对应 Android `ScanConfigEntity`）。
struct ScanConfig: Identifiable, Hashable {
    var id: Int64 = 0
    var name: String = ""
    var folderUri: String = ""          // iOS 下保存安全作用域书签 Data 的 base64
    var folderName: String = ""         // 可阅读路径，仅用于界面反显
    var fileTypes: String = "txt"
    var minSizeKb: Int = 0
    var recursive: Bool = true
    var exactHash: Bool = false
    var excludedFolders: String = ""
    var excludedTitles: String = ""        // 排除的原始书名，多个逗号/换行分隔，书名完全相等才跳过
    var excludedTitleKeywords: String = "" // 排除的书名词汇，多个逗号/换行分隔，书名包含该词汇即跳过
    var scanMode: String = "quick"       // "quick" | "deep"
}

/// 一次扫描对应一个「文库」（对应 Android `ScanRunEntity`）。
struct ScanRun: Identifiable {
    var id: Int64 = 0
    var name: String = ""
    var folderUri: String = ""
    var folderName: String = ""
    var fileTypes: String = "txt"
    var createdAt: Int64 = 0
    var fileCount: Int = 0
}

/// 关键词替换规则（对应 Android `KeywordReplaceRuleEntity`）。
struct KeywordReplaceRule: Identifiable {
    var id: Int64 = 0
    var scope: String = "scan"   // "scan"=文件名阶段, "parse"=解析阶段(书名/作者/进度/来源)
    var pattern: String = ""
    var replacement: String = ""
    var sortOrder: Int = 0
    var enabled: Bool = true
    var createdAt: Int64 = 0
}

/// 勾选重复规则配置（对应 Android `DupRuleConfigEntity`）。
struct DupRuleConfig: Identifiable {
    var id: Int64 = 0
    var ruleKey: String = ""
    var ruleName: String = ""
    var enabled: Bool = true
    var desc: String = ""
    var isBuiltin: Bool = false
    var conditions: String? = nil
    var action: String? = nil   // "check" | "protect"
    var sortOrder: Int = 0
    var createdAt: Int64 = 0
    var updatedAt: Int64 = 0
}

/// 勾选重复计算所需的轻量投影（对应 Android `DuplicateRow`）。
struct DuplicateRow {
    let id: Int64
    let fileName: String
    let title: String
    let author: String
    let progress: String
    let source: String
    let fileSize: Int64
    let createdAt: Int64
    /// 文件在文件系统中的最后修改时间（毫秒时间戳）。判断“新旧”时优先使用，避免扫描入库顺序干扰。
    let fileDate: Int64
    /// 内容哈希（扫描时计算，可能为空）。rule_hash 内容哈希去重规则使用：哈希相同且非最新的文件额外勾选。
    let contentHash: String
}

/// 合集分组头（按书名聚合的统计结果，非数据库实体）。对齐安卓：合集仅按书名(title)分组。
struct NovelGroup: Identifiable {
    var id: String { title }
    var title: String
    var fileCount: Int
    var totalSize: Int64
    var checkedCount: Int
}

/// 操作日志条目（对应 `operation_log` 表）。
struct LogEntry: Identifiable {
    var id: Int64 = 0
    var time: Int64 = 0
    var level: String = ""
    var tag: String = ""
    var message: String = ""
}
