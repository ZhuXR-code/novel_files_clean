import Foundation

/// 调试日志：保留内存环形缓冲供开发期查看；正式操作日志写入数据库 `operation_log`（见 DatabaseManager.logOperation）。
final class LogUtil {
    static let shared = LogUtil()
    private let lock = NSLock()
    private var buffer: [(time: Int64, level: String, tag: String, message: String)] = []
    private let max = 500

    static func i(_ tag: String, _ message: String) { shared.append("I", tag, message) }
    static func e(_ tag: String, _ message: String) { shared.append("E", tag, message) }
    static func d(_ tag: String, _ message: String) { shared.append("D", tag, message) }

    private func append(_ level: String, _ tag: String, _ message: String) {
        lock.lock()
        buffer.append((Int64(Date().timeIntervalSince1970 * 1000), level, tag, message))
        if buffer.count > max { buffer.removeFirst() }
        lock.unlock()
    }

    func recent() -> [(time: Int64, level: String, tag: String, message: String)] {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }

}
