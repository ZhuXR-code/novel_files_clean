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

    /// 把 SAF content:// URI 或本地路径转成更易读的形式，仅用于页面展示。
    /// 不改变底层存储：DB 中仍是原始 URI，导出/打开文件时也仍用原始路径。
    ///
    /// - 解码 %2F / %20 / %3A 等 URL 编码（让中文文件名、空格显示正常）；
    /// - 优先取 SAF document id（/document/ 之后）作为文件真实相对路径；
    /// - 去掉存储卷标识（primary: / MuMuShared: 等），只保留人类可读的目录与文件名。
    static func toHumanReadablePath(_ raw: String) -> String {
        if raw.isEmpty { return raw }
        // 1) 解码 URL 编码（等价于 Android 的 Uri.decode）
        let decoded = raw.removingPercentEncoding ?? raw
        // 2) 取 /document/ 之后的部分（SAF 文档真实相对路径）
        let docMarker = "/document/"
        let docPart: String
        if let range = decoded.range(of: docMarker), !range.upperBound.equalTo(decoded.endIndex) {
            docPart = String(decoded[range.upperBound...])
        } else {
            docPart = decoded
        }
        // 3) 去掉开头的存储卷标识（形如 "primary:" / "MuMuShared:"）
        let cleaned = docPart.replacingOccurrences(of: "^[A-Za-z0-9]+:", with: "", options: .regularExpression)
        return cleaned.isEmpty ? decoded : cleaned
    }
}
