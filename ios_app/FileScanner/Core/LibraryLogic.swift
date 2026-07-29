import Foundation

/// 列表/合集分页相关的纯计算（对齐 Android `LibraryLogic`）。
enum LibraryLogic {
    /// 计算总页数：至少 1 页。
    static func computePageCount(total: Int, pageSize: Int) -> Int {
        precondition(pageSize > 0, "pageSize 必须 > 0")
        return ((total + pageSize - 1) / pageSize).coerceAtLeast(1)
    }

    /// 解析合集「排除书名」输入：按逗号/换行切分，去空白、丢弃空项。
    static func parseExcludeNames(_ raw: String) -> [String] {
        raw.components(separatedBy: CharacterSet(charactersIn: ",\n")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// 当前页码越界回退：夹到 [0, pageCount-1]。
    static func adjustPage(_ page: Int, pageCount: Int) -> Int {
        return page.clamped(to: 0...(pageCount - 1).coerceAtLeast(0))
    }
}
