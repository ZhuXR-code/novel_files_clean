import Foundation

/// 全局设置（对齐 Android `PreferencesUtil`，底层 UserDefaults）。
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @Published var themeMode: String { didSet { ud.set(themeMode, forKey: "theme_mode"); LogUtil.d("Preferences", "设置 themeMode=\(themeMode)") } }
    @Published var scanFileTypes: String { didSet { ud.set(scanFileTypes, forKey: "scan_file_types"); LogUtil.d("Preferences", "设置 scanFileTypes=\(scanFileTypes)") } }
    @Published var minFileSizeKb: Int { didSet { ud.set(minFileSizeKb, forKey: "min_file_size_kb"); LogUtil.d("Preferences", "设置 minFileSizeKb=\(minFileSizeKb)") } }
    @Published var recursive: Bool { didSet { ud.set(recursive, forKey: "recursive"); LogUtil.d("Preferences", "设置 recursive=\(recursive)") } }
    @Published var groupMinCount: Int { didSet { ud.set(groupMinCount, forKey: "group_min_count"); LogUtil.d("Preferences", "设置 groupMinCount=\(groupMinCount)") } }
    @Published var groupMaxCount: Int { didSet { ud.set(groupMaxCount, forKey: "group_max_count"); LogUtil.d("Preferences", "设置 groupMaxCount=\(groupMaxCount)") } }
    @Published var groupExcludeNames: String { didSet { ud.set(groupExcludeNames, forKey: "group_exclude_names"); LogUtil.d("Preferences", "设置 groupExcludeNames=\(groupExcludeNames)") } }
    /// 合集排序方式（对齐安卓 GroupSortMode）：count_desc/count_asc/size_desc/size_asc/name_asc/name_desc/date_newest/date_oldest
    @Published var groupSort: String { didSet { ud.set(groupSort, forKey: "group_sort"); LogUtil.d("Preferences", "设置 groupSort=\(groupSort)") } }
    /// 勾选过的文件/合集是否自动排到最前面（对齐安卓 auto_sort_checked，默认关闭）
    @Published var checkedSortToFront: Bool { didSet { ud.set(checkedSortToFront, forKey: "checked_sort_to_front"); LogUtil.d("Preferences", "设置 checkedSortToFront=\(checkedSortToFront)") } }
    /// 已标记「重复文件名」的文件是否自动排到列表最前面（默认开启）
    @Published var markedSortToFront: Bool { didSet { ud.set(markedSortToFront, forKey: "marked_sort_to_front"); LogUtil.d("Preferences", "设置 markedSortToFront=\(markedSortToFront)") } }
    @Published var kwSeedDone: Bool { didSet { ud.set(kwSeedDone, forKey: "kw_seed_done"); LogUtil.d("Preferences", "设置 kwSeedDone=\(kwSeedDone)") } }
    @Published var privacyAgreed: Bool { didSet { ud.set(privacyAgreed, forKey: "privacy_agreed"); LogUtil.i("Preferences", "设置 privacyAgreed=\(privacyAgreed)") } }
    /// 买断制：是否已永久解锁全部功能。
    @Published var unlocked: Bool { didSet { ud.set(unlocked, forKey: "bk_unlocked"); LogUtil.i("Preferences", "设置 unlocked=\(unlocked)") } }

    private let ud = UserDefaults.standard

    init() {
        themeMode = ud.string(forKey: "theme_mode") ?? "system"
        scanFileTypes = ud.string(forKey: "scan_file_types") ?? "txt"
        minFileSizeKb = ud.integer(forKey: "min_file_size_kb")
        recursive = ud.object(forKey: "recursive") as? Bool ?? true
        groupMinCount = ud.integer(forKey: "group_min_count")
        groupMaxCount = ud.object(forKey: "group_max_count") as? Int ?? -1
        groupExcludeNames = ud.string(forKey: "group_exclude_names") ?? ""
        groupSort = ud.string(forKey: "group_sort") ?? "count_desc"
        checkedSortToFront = ud.bool(forKey: "checked_sort_to_front")
        markedSortToFront = ud.object(forKey: "marked_sort_to_front") as? Bool ?? true
        kwSeedDone = ud.bool(forKey: "kw_seed_done")
        privacyAgreed = ud.bool(forKey: "privacy_agreed")
        unlocked = ud.bool(forKey: "bk_unlocked")
        LogUtil.i("Preferences", "初始化完成：theme=\(themeMode) types=\(scanFileTypes) recursive=\(recursive) privacy=\(privacyAgreed) unlocked=\(unlocked)")
    }

    func setGroupFilter(minCount: Int, maxCount: Int, excludeNames: String) {
        LogUtil.d("Preferences", "设置合集筛选 min=\(minCount) max=\(maxCount) exclude=\(excludeNames)")
        groupMinCount = minCount.coerceAtLeast(0)
        groupMaxCount = maxCount
        groupExcludeNames = excludeNames
    }

    var fontScaleFactor: CGFloat {
        return 1.0
    }
}
