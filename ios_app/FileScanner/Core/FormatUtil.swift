import Foundation

/// 复用 Android `FormatUtil` 的格式化逻辑。
enum FormatUtil {
    static func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024.0)
    }

    /// 把毫秒时间戳格式化为 "yyyy-MM-dd" 短日期；<=0 返回 "无日期"。
    static func formatFileDate(_ timestamp: Int64?) -> String {
        guard let ts = timestamp, ts > 0 else { return "无日期" }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date(timeIntervalSince1970: TimeInterval(ts) / 1000.0))
    }
}
