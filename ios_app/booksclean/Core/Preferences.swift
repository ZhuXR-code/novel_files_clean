import Foundation

/// 全局设置（对齐 Android `PreferencesUtil`，底层 UserDefaults）。
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @Published var themeMode: String { didSet { ud.set(themeMode, forKey: "theme_mode") } }
    @Published var scanFileTypes: String { didSet { ud.set(scanFileTypes, forKey: "scan_file_types") } }
    @Published var minFileSizeKb: Int { didSet { ud.set(minFileSizeKb, forKey: "min_file_size_kb") } }
    @Published var recursive: Bool { didSet { ud.set(recursive, forKey: "recursive") } }
    @Published var groupMinCount: Int { didSet { ud.set(groupMinCount, forKey: "group_min_count") } }
    @Published var groupMaxCount: Int { didSet { ud.set(groupMaxCount, forKey: "group_max_count") } }
    @Published var groupExcludeNames: String { didSet { ud.set(groupExcludeNames, forKey: "group_exclude_names") } }
    @Published var fontScaleMode: String { didSet { ud.set(fontScaleMode, forKey: "font_scale") } }
    @Published var previewScrollbarMode: String { didSet { ud.set(previewScrollbarMode, forKey: "preview_scrollbar_mode") } }
    /// 合集排序方式（对齐安卓 GroupSortMode）：count_desc/count_asc/size_desc/size_asc/name_asc/name_desc/date_newest/date_oldest
    @Published var groupSort: String { didSet { ud.set(groupSort, forKey: "group_sort") } }
    /// 勾选过的文件/合集是否自动排到最前面（对齐安卓 auto_sort_checked，默认关闭）
    @Published var checkedSortToFront: Bool { didSet { ud.set(checkedSortToFront, forKey: "checked_sort_to_front") } }
    @Published var kwSeedDone: Bool { didSet { ud.set(kwSeedDone, forKey: "kw_seed_done") } }
    @Published var privacyAgreed: Bool { didSet { ud.set(privacyAgreed, forKey: "privacy_agreed") } }

    private let ud = UserDefaults.standard

    init() {
        themeMode = ud.string(forKey: "theme_mode") ?? "system"
        scanFileTypes = ud.string(forKey: "scan_file_types") ?? "txt"
        minFileSizeKb = ud.integer(forKey: "min_file_size_kb")
        recursive = ud.object(forKey: "recursive") as? Bool ?? true
        groupMinCount = ud.integer(forKey: "group_min_count")
        groupMaxCount = ud.object(forKey: "group_max_count") as? Int ?? -1
        groupExcludeNames = ud.string(forKey: "group_exclude_names") ?? ""
        fontScaleMode = ud.string(forKey: "font_scale") ?? "standard"
        previewScrollbarMode = ud.string(forKey: "preview_scrollbar_mode") ?? "vertical"
        groupSort = ud.string(forKey: "group_sort") ?? "count_desc"
        checkedSortToFront = ud.bool(forKey: "checked_sort_to_front")
        kwSeedDone = ud.bool(forKey: "kw_seed_done")
        privacyAgreed = ud.bool(forKey: "privacy_agreed")
    }

    func setGroupFilter(minCount: Int, maxCount: Int, excludeNames: String) {
        groupMinCount = minCount.coerceAtLeast(0)
        groupMaxCount = maxCount
        groupExcludeNames = excludeNames
    }

    var fontScaleFactor: CGFloat {
        switch fontScaleMode {
        case "small": return 0.85
        case "large": return 1.2
        default: return 1.0
        }
    }
}
