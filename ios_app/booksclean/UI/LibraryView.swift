import SwiftUI
import UIKit

private let SORT_OPTIONS: [(String, String)] = [
    ("created_at", "扫描顺序"), ("file_size", "文件大小"), ("file_name", "文件名"),
    ("title", "书名"), ("author", "作者"), ("progress", "进度"), ("source", "来源")
]

/// 合集排序选项（对齐安卓 LibraryViewModel.GroupSortMode 的 8 档）
private let GROUP_SORT_OPTIONS: [(String, String)] = [
    ("count_desc", "文件数量（多→少）"), ("count_asc", "文件数量（少→多）"),
    ("size_desc", "合集大小（大→小）"), ("size_asc", "合集大小（小→大）"),
    ("name_asc", "合集名称（A→Z）"), ("name_desc", "合集名称（Z→A）"),
    ("date_newest", "最新文件（新→旧）"), ("date_oldest", "最旧文件（旧→新）")
]

struct FileRow: View {
    let file: ScannedFile
    let onToggleCheck: () -> Void
    let onToggleMark: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { onToggleCheck() } label: {
                Image(systemName: file.checked == 1 ? "checkmark.circle.fill" : "circle")
                    .fsFont(.title3).foregroundColor(file.checked == 1 ? .fsPrimary : .fsSecondaryLabel)
            }
            VStack(alignment: .leading, spacing: 3) {
                // 对齐安卓：书名优先为主标题，原文件名作为副标题
                if !file.title.isEmpty {
                    Text("《\(file.title)》").fsFont(.subheadline).fontWeight(.medium).lineLimit(1)
                }
                Text(file.fileName).fsFont(file.title.isEmpty ? .subheadline : .caption).foregroundColor(file.title.isEmpty ? .primary : .fsSecondaryLabel).lineLimit(1)
                HStack(spacing: 8) {
                    if !file.author.isEmpty { Text("作者: \(file.author)").fsFont(.caption).foregroundColor(.fsSecondaryLabel) }
                    if !file.progress.isEmpty { Text("进度: \(file.progress)").fsFont(.caption).foregroundColor(.fsSecondaryLabel) }
                    if !file.source.isEmpty { Text("来源: \(file.source)").fsFont(.caption).foregroundColor(.fsSecondaryLabel) }
                }
                Text(FormatUtil.formatSize(file.fileSize) + " · " + FormatUtil.formatFileDate(file.fileDate))
                    .fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }   // 仅文字区域点击进入详情，复选框/星星各自独立
            Spacer(minLength: 4)
            Button { onToggleMark() } label: {
                Image(systemName: file.marked == 1 ? "star.fill" : "star")
                    .foregroundColor(file.marked == 1 ? .yellow : .fsSecondaryLabel)
            }
            .buttonStyle(.plain)
        }
    }
}

// 分页栏（对齐安卓 PageNavBar）：每页行数自定义、跳转到指定页、首页/上页/下页/末页
struct PageNavBar: View {
    @Binding var page: Int
    let pageCount: Int
    let totalItems: Int
    @Binding var pageSize: Int
    let onPageChange: () -> Void
    let onPageSizeChange: () -> Void

    @State private var pageSizeText: String = ""
    @State private var jumpText: String = ""

    private var safePageCount: Int { max(pageCount, 1) }
    private var currentPage1: Int { min(max(page, 0), safePageCount - 1) + 1 }

    var body: some View {
        VStack(spacing: 6) {
            // 第一行：每页行数 + 总数 + 页码
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("每页").fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                    TextField("\(pageSize)", text: $pageSizeText)
                        .fsFont(.caption2).frame(width: 46)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Text("行").fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                    Button("应用") {
                        if let v = Int(pageSizeText), v >= 10, v <= 2000 {
                            pageSize = v
                            page = 0
                            onPageSizeChange()
                        }
                        pageSizeText = ""
                        hideKeyboard()
                    }
                    .fsFont(.caption2)
                }
                Spacer()
                Text("共 \(totalItems) 条 · 第 \(currentPage1)/\(safePageCount) 页")
                    .fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
            }
            // 第二行：翻页 + 跳页
            HStack(spacing: 6) {
                navButton("«", disabled: currentPage1 <= 1) { jump(to: 0) }
                navButton("‹", disabled: currentPage1 <= 1) { jump(to: currentPage1 - 2) }
                navButton("›", disabled: currentPage1 >= safePageCount) { jump(to: currentPage1) }
                navButton("»", disabled: currentPage1 >= safePageCount) { jump(to: safePageCount - 1) }
                Spacer()
                HStack(spacing: 4) {
                    Text("跳至").fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                    TextField("", text: $jumpText)
                        .fsFont(.caption2).frame(width: 42)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Text("页").fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                    Button("跳转") {
                        if let v = Int(jumpText), v >= 1, v <= safePageCount {
                            jump(to: v - 1)
                        }
                        jumpText = ""
                        hideKeyboard()
                    }
                    .fsFont(.caption2)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.fsTertiaryBg)
    }

    private func navButton(_ label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).fsFont(.callout).frame(minWidth: 34)
                .padding(.vertical, 4).background(Color.fsPrimary.opacity(disabled ? 0.3 : 1))
                .foregroundColor(.white).cornerRadius(8)
        }
        .disabled(disabled)
    }

    private func jump(to p: Int) {
        let clamped = min(max(p, 0), safePageCount - 1)
        guard clamped != page else { return }
        page = clamped
        onPageChange()
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// 步骤指示器（对齐安卓文库页顶部的「扫描→合集→勾选重复→确认→删除」步骤条）
private let LIB_STEPS = ["扫描", "合集", "勾选重复", "确认", "删除"]
struct LibraryStepBar: View {
    let current: Int
    let canGroup: Bool
    let canDup: Bool
    let canDelete: Bool
    let onStep: (Int) -> Void   // 点击可操作节点：1=合集 2=勾选重复 4=删除

    private func clickable(_ i: Int) -> Bool {
        (i == 1 && canGroup) || (i == 2 && canDup) || (i == 4 && canDelete)
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(LIB_STEPS.indices, id: \.self) { i in
                Button {
                    if clickable(i) { onStep(i) }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(i <= current ? Color.fsPrimary : Color.fsTertiaryBg)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Text("\(i + 1)").fsFontSize(10).foregroundColor(i <= current ? .white : .fsSecondaryLabel)
                            )
                        if i < LIB_STEPS.count - 1 {
                            Text(LIB_STEPS[i]).fsFont(.caption2).foregroundColor(i < current ? .fsPrimary : .fsSecondaryLabel)
                            Image(systemName: "chevron.right").fsFont(.caption2).foregroundColor(.fsTertiaryBg)
                        } else {
                            Text(LIB_STEPS[i]).fsFont(.caption2).foregroundColor(i < current ? .fsPrimary : .fsSecondaryLabel)
                        }
                    }
                    .opacity(clickable(i) ? 1 : (i <= current ? 1 : 0.45))
                }
                .buttonStyle(.plain)
                .disabled(!clickable(i))
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)   // 整体在顶部栏内居中
    }
}

struct LibraryView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var prefs: Preferences
    let runId: Int64

    @State private var mode = UserDefaults.standard.string(forKey: "lib_mode") ?? "list" // "list" | "group"
    @State private var files: [ScannedFile] = []
    @State private var groups: [NovelGroup] = []
    @State private var total = 0
    @State private var page = 0
    @State private var pageCount = 1
    @State private var pageSize = 100          // 对齐安卓默认每页 100 行，可自定义
    @State private var groupTotal = 0
    @State private var groupPageCount = 1
    @State private var sortBy = "created_at"
    @State private var ascending = false
    @State private var search = ""
    @State private var titleFilter = ""
    @State private var authorFilter = ""
    @State private var progressFilter = ""
    @State private var sourceFilter = ""
    @State private var showFilter = false
    @State private var selectAllOnPage = false
    @State private var selectedFilter = "all"     // all/checked/unchecked/marked/unmarked
    @State private var autoCollapse = false
    @State private var showGroupSettings = false
    @State private var toastText: String? = nil
    @State private var showCheckPrompt = false
    @State private var showExportSheet = false
    @State private var running = false
    @State private var exportAll = false
    @State private var exportColumns: Set<String> = ["name", "title", "author", "size", "path", "date", "extra", "checked", "marked"]

    // 派生统计：顶部步骤条与汇总文案使用
    @State private var checkedCount = 0
    @State private var totalCount = 0
    @State private var groupChecked: [String: Int] = [:]   // "title\u{0}author" -> 已勾选数
    @State private var runFileCount = 0                     // 文库总文件数

    /// 当前步骤节点：0 扫描 / 1 合集 / 2 勾选重复 / 3 确认 / 4 删除。
    /// 随用户操作前进而点亮、退回而熄灭。
    private var currentStep: Int {
        var s = 0
        if mode == "group" { s = max(s, 1) }
        if checkedCount > 0 { s = max(s, 3) }
        return s
    }
    private var canStepGroup: Bool { mode != "group" }
    private var canStepDup: Bool { mode == "group" && !running }
    private var canStepDelete: Bool { checkedCount > 0 }


    var body: some View {
        VStack(spacing: 0) {
            // 步骤指示器（对齐安卓文库顶部步骤条，节点可点击）
            LibraryStepBar(
                current: currentStep,
                canGroup: canStepGroup,
                canDup: canStepDup,
                canDelete: canStepDelete,
                onStep: handleStep
            )
            .padding(.vertical, 6)

            // 汇总文案（对齐安卓 run_summary / group_summary / selected_count）
            summaryBar
                .padding(.horizontal)
                .padding(.bottom, 4)

            Picker("模式", selection: $mode) {
                Text("列表").tag("list")
                Text("合集").tag("group")
            }
            .pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 6)
            .onChange(of: mode) { newMode in
                UserDefaults.standard.set(newMode, forKey: "lib_mode")
                page = 0
                reload()
            }

            // 筛选 chips（对齐安卓文库筛选行）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("全部", "all")
                    filterChip("已勾选", "checked")
                    filterChip("未勾选", "unchecked")
                    filterChip("已标记", "marked")
                    filterChip("未标记", "unmarked")
                }
                .padding(.horizontal, 4)
            }
            .padding(.bottom, 6)

            if mode == "list" { listContent } else { groupContent }

            // 分页栏（对齐安卓 PageNavBar：每页行数自定义、跳页、首页/上页/下页/末页）
            let totalItems = mode == "list" ? total : groupTotal
            let pgCount = mode == "list" ? pageCount : groupPageCount
            PageNavBar(
                page: $page,
                pageCount: pgCount,
                totalItems: totalItems,
                pageSize: $pageSize,
                onPageChange: { reload() },
                onPageSizeChange: { reload() }
            )
        }
        .overlay(alignment: .bottom) {
            if let t = toastText {
                Text(t)
                    .fsFont(.caption).foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(16)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .navigationTitle("文库")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .searchable(text: $search, prompt: "搜索文件名/书名/作者")
        .onSubmit(of: .search) { reload() }
        .onChange(of: sortBy) { _ in reload() }
        .onChange(of: ascending) { _ in reload() }
        .onChange(of: search) { v in if v.isEmpty { reload() } }
        .onChange(of: selectedFilter) { _ in
            // 切换筛选时回到第 1 页，否则停留在旧页码时新筛选结果可能更少，
            // 会显示空白页，让人误以为「筛选没生效」。
            page = 0
            reload()
        }
        .onAppear { reload() }
        .sheet(isPresented: $showFilter) { filterSheet }
        .sheet(isPresented: $showGroupSettings) { groupSettingsSheet }
        .sheet(isPresented: $showExportSheet) { exportSheet }
    }

    private func filterChip(_ title: String, _ key: String) -> some View {
        Button {
            selectedFilter = key
        } label: {
            Text(title)
                .fsFont(.caption).fontWeight(.medium)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selectedFilter == key ? Color.fsPrimary : Color.fsTertiaryBg)
                .foregroundColor(selectedFilter == key ? .white : .fsPrimary)
                .cornerRadius(14)
        }
    }

    /// 空状态引导（对齐安卓空状态：图标 + 说明 + 操作入口，minimalism）。
    private func emptyStateView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray")
                .fsFontSize(48)
                .foregroundColor(.fsSecondaryLabel)
            Text(message)
                .fsFont(.subheadline)
                .foregroundColor(.fsSecondaryLabel)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 列表模式
    private var listContent: some View {
        Group {
            if files.isEmpty {
                emptyStateView(message: "暂无文件\n\n可返回首页选择文件夹扫描，或使用顶部「一键勾选重复」按规则批量勾选。")
            } else if isPad {
                // iPad：多列网格，提升大屏利用率（swipeActions 在 Grid 不可用，改点击进入详情后预览）
                GeometryReader { geo in
                    let cols = adaptiveColumns(for: geo.size.width, minItemWidth: 380)
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: cols), spacing: 12) {
                            ForEach(files) { f in
                                FileRow(
                                    file: f,
                                    onToggleCheck: { toggleCheck(f) },
                                    onToggleMark: { toggleMark(f) },
                                    onTap: { router.navigate(.fileDetail(id: f.id)) }
                                )
                                .padding(12)
                                .background(Color.fsSecondaryBg).cornerRadius(12)
                            }
                        }
                        .padding(12)
                    }
                }
            } else {
                List {
                    ForEach(files) { f in
                        FileRow(
                            file: f,
                            onToggleCheck: { toggleCheck(f) },
                            onToggleMark: { toggleMark(f) },
                            onTap: { router.navigate(.fileDetail(id: f.id)) }
                        )
                        .swipeActions(edge: .leading) {
                            Button { router.navigate(.filePreview(id: f.id, mode: "head")) } label: { Label("预览", systemImage: "eye") }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: 合集模式
    private var groupContent: some View {
        Group {
            if groups.isEmpty {
                emptyStateView(message: "暂无合集\n\n合集按「书名 / 作者」自动归并。可先到列表模式扫描并解析文件，或在更多菜单中进入「合集设置」调整分组规则。")
            } else if isPad {
                // iPad：多列卡片网格
                GeometryReader { geo in
                    let cols = adaptiveColumns(for: geo.size.width, minItemWidth: 320)
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: cols), spacing: 12) {
                            ForEach(groups) { g in
                                GroupCardView(g: g, groupChecked: groupChecked, onToggle: {
                                    let key = "\(g.title)\u{0000}\(g.author)"
                                    let checked = groupChecked[key] ?? 0
                                    let allChecked = checked >= g.fileCount && g.fileCount > 0
                                    toggleGroupChecked(title: g.title, author: g.author, allChecked: allChecked)
                                }, onTap: { router.navigate(.groupFiles(runId: runId, title: g.title == "(无书名)" ? "" : g.title, author: g.author)) })
                                .padding(12)
                                .background(Color.fsSecondaryBg).cornerRadius(12)
                            }
                        }
                        .padding(12)
                    }
                }
            } else {
                List {
                    ForEach(groups) { g in
                        HStack {
                            // 三态复选框：空白=未勾选 / √=全部勾选 / -=部分勾选
                            let key = "\(g.title)\u{0000}\(g.author)"
                            let checked = groupChecked[key] ?? 0
                            let allChecked = checked >= g.fileCount && g.fileCount > 0
                            let someChecked = checked > 0 && !allChecked
                            Button {
                                toggleGroupChecked(title: g.title, author: g.author, allChecked: allChecked)
                            } label: {
                                Image(systemName: allChecked ? "checkmark.square.fill" : (someChecked ? "minus.square.fill" : "square"))
                                    .foregroundColor(allChecked || someChecked ? .fsPrimary : .fsSecondaryLabel)
                                    .font(.system(size: 18))
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(g.title).fsFont(.subheadline).fontWeight(.medium)
                                Text("作者: \(g.author) · \(g.fileCount) 本 · \(FormatUtil.formatSize(g.totalSize))")
                                    .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                            }
                            Spacer()
                            if g.checkedCount > 0 {
                                Text("勾选 \(g.checkedCount)").fsFont(.caption).foregroundColor(.red)
                            }
                            Image(systemName: "chevron.right").foregroundColor(.fsSecondaryLabel)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { router.navigate(.groupFiles(runId: runId, title: g.title == "(无书名)" ? "" : g.title, author: g.author)) }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // 合集卡片（iPad 网格用）
    private func GroupCardView(g: NovelGroup, groupChecked: [String: Int], onToggle: @escaping () -> Void, onTap: @escaping () -> Void) -> some View {
        let key = "\(g.title)\u{0000}\(g.author)"
        let checked = groupChecked[key] ?? 0
        let allChecked = checked >= g.fileCount && g.fileCount > 0
        let someChecked = checked > 0 && !allChecked
        return HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: allChecked ? "checkmark.square.fill" : (someChecked ? "minus.square.fill" : "square"))
                    .foregroundColor(allChecked || someChecked ? .fsPrimary : .fsSecondaryLabel)
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                Text(g.title).fsFont(.subheadline).fontWeight(.medium)
                Text("作者: \(g.author) · \(g.fileCount) 本 · \(FormatUtil.formatSize(g.totalSize))")
                    .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
            }
            Spacer(minLength: 4)
            if g.checkedCount > 0 {
                Text("勾选 \(g.checkedCount)").fsFont(.caption).foregroundColor(.red)
            }
            Image(systemName: "chevron.right").foregroundColor(.fsSecondaryLabel)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var toolbarItems: some ToolbarContent {
        Group {
            // 常驻操作（对齐安卓文库顶部图标栏：勾选重复 / 删除选中 / 更多）
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    selectDuplicates()
                } label: { Image(systemName: "checkmark.circle") }
                .help("一键勾选重复（按书名/作者相同）")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    let ids = FileRepository.shared.getCheckedIds(runId: runId)
                    guard !ids.isEmpty else { return }
                    // 跳转删除确认页，让用户选择「仅删除记录」或「记录与源文件一起删除」
                    router.navigate(.deleteConfirm(runId: runId, ids: ids, physical: false))
                } label: { Image(systemName: "trash") }
                .help("删除勾选文件")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(selectAllOnPage ? "取消本页勾选" : "勾选本页") { toggleSelectAllPage() }
                    Menu("排序字段") {
                        ForEach(SORT_OPTIONS, id: \.0) { opt in
                            Button { sortBy = opt.0 } label: { Text(opt.1) }
                        }
                    }
                    Button(ascending ? "切换为降序" : "切换为升序") { ascending.toggle() }
                    Button("筛选") { showFilter = true }
                    Button("合集设置") { showGroupSettings = true }
                    // 合集排序：对齐安卓，仅在合集模式下出现
                    if mode == "group" {
                        Menu("合集排序") {
                            ForEach(GROUP_SORT_OPTIONS, id: \.0) { opt in
                                Button {
                                    prefs.groupSort = opt.0
                                    page = 0
                                    reload()
                                } label: {
                                    Label(opt.1, systemImage: prefs.groupSort == opt.0 ? "checkmark" : "")
                                }
                            }
                        }
                    }
                    // 勾选置顶（对齐安卓 auto_sort_checked 开关）
                    Button {
                        prefs.checkedSortToFront.toggle()
                        page = 0
                        reload()
                        toast(prefs.checkedSortToFront ? "勾选文件已置顶" : "已取消勾选置顶")
                    } label: {
                        Label("勾选文件排到前面", systemImage: prefs.checkedSortToFront ? "checkmark" : "")
                    }
                    // 标记置顶（新增：已标记重复文件名的文件排到列表最前）
                    Button {
                        prefs.markedSortToFront.toggle()
                        page = 0
                        reload()
                        toast(prefs.markedSortToFront ? "标记文件已置顶" : "已取消标记置顶")
                    } label: {
                        Label("标记文件排到前面", systemImage: prefs.markedSortToFront ? "checkmark" : "")
                    }

                    Divider()
                    // 标记重复（独立出来，置顶在更多操作顶层）
                    Menu("标记重复") {
                        Button("标记重复文件名（同名）") {
                            let n = FileRepository.shared.markDuplicateFileNames(runId: runId)
                            toast(n > 0 ? "已标记 \(n) 个同名重复文件" : "没有同名重复文件")
                            reload()
                        }
                        Button("标记重复（书名+作者相同）") {
                            let n = FileRepository.shared.markDuplicatesByName(runId: runId)
                            toast(n > 0 ? "已标记 \(n) 个书名/作者相同的重复文件" : "没有书名/作者相同的重复文件")
                            reload()
                        }
                    }
                    // 按内容哈希相同（对齐安卓文库「更多操作」新增的两项：标记/勾选内容哈希相同但时间更早的文件）
                    Menu("按内容哈希相同") {
                        Button("标记内容哈希相同但较早的文件") {
                            let n = FileRepository.shared.markDuplicatesByHash(runId: runId)
                            if n < 0 {
                                toast("该文库未扫描内容哈希，无法按哈希标记；请在深度扫描中开启「内容哈希」后重新扫描")
                            } else if n > 0 {
                                toast("已按内容哈希标记 \(n) 个较早文件")
                            } else {
                                toast("未发现内容哈希相同的重复文件")
                            }
                            reload()
                        }
                        Button("勾选内容哈希相同但较早的文件") {
                            let n = FileRepository.shared.checkDuplicatesByHash(runId: runId)
                            if n < 0 {
                                toast("该文库未扫描内容哈希，无法按哈希勾选；请在深度扫描中开启「内容哈希」后重新扫描")
                            } else if n > 0 {
                                toast("已按内容哈希勾选 \(n) 个较早文件")
                                reload()
                            } else {
                                toast("未发现内容哈希相同的重复文件")
                                reload()
                            }
                        }
                    }
                    // 批量操作（对齐安卓文库「更多」菜单）
                    Menu("批量操作") {
                        Button("标记已勾选文件") {
                            let ids = FileRepository.shared.getCheckedIds(runId: runId)
                            FileRepository.shared.updateMarked(ids: ids, marked: true)
                            toast("已标记 \(ids.count) 个文件")
                            reload()
                        }
                        Button("清除全部勾选") {
                            FileRepository.shared.resetChecked(runId: runId)
                            selectAllOnPage = false
                            toast("已清除全部勾选")
                            reload()
                        }
                        Button("清除全部标记") {
                            FileRepository.shared.resetMarked(runId: runId)
                            toast("已清除全部标记")
                            reload()
                        }
                    }

                    Divider()
                    Button("一键清理") { router.navigate(.oneClickExisting(runId: runId)) }
                    Divider()
                    Button { showExportSheet = true } label: { Label("导出列表", systemImage: "square.and.arrow.up") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button("设置") { router.navigate(.settings) }
                    Button("帮助") { router.navigate(.help) }
                } label: { Image(systemName: "gearshape") }
            }
        }
    }

    private var filterSheet: some View {
        NavigationStack {
            MaxWidthContainer {
                Form {
                    Section("前缀筛选（留空=不筛选）") {
                        TextField("书名前缀", text: $titleFilter)
                        TextField("作者前缀", text: $authorFilter)
                        TextField("进度前缀", text: $progressFilter)
                        TextField("来源前缀", text: $sourceFilter)
                    }
                    Section("合集数量范围") {
                        Stepper("最小数量: \(prefs.groupMinCount)", value: $prefs.groupMinCount, in: 0...1000)
                        TextField("排除书名（逗号分隔）", text: $prefs.groupExcludeNames)
                    }
                    Section {
                        Toggle("自动置顶合集", isOn: $autoCollapse)
                    }
                }
            }
            .navigationTitle("筛选").navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("应用") { showFilter = false; page = 0; reload() }
                }
            }
        }
    }

    // 合集设置（对齐安卓文库「合集设置」：最小/最大数量、排除书名）
    private var groupSettingsSheet: some View {
        NavigationStack {
            MaxWidthContainer {
                Form {
                    Section("合集数量范围") {
                        Stepper("最小数量: \(prefs.groupMinCount)", value: $prefs.groupMinCount, in: 0...1000)
                        Toggle("限制最大数量", isOn: Binding(get: { prefs.groupMaxCount >= 0 }, set: { v in prefs.groupMaxCount = v ? 500 : -1 }))
                        if prefs.groupMaxCount >= 0 {
                            Stepper("最大数量: \(prefs.groupMaxCount)", value: $prefs.groupMaxCount, in: 0...100000)
                        }
                        TextField("排除书名（逗号分隔）", text: $prefs.groupExcludeNames)
                    }
                }
            }
            .navigationTitle("合集设置").navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { showGroupSettings = false; reload() }
                }
            }
        }
    }

    // MARK: - 导出列表弹框（对齐安卓 ListExportUtil：列选择 + 本页/全部）
    private var exportSheet: some View {
        let allColumns = [
            ("name", "文件名"), ("title", "书名"), ("author", "作者"), ("size", "大小"),
            ("path", "路径"), ("date", "日期"), ("extra", "其他"), ("checked", "勾选状态"), ("marked", "标记状态")
        ]
        return NavigationStack {
            Form {
                Section("导出范围") {
                    Picker("范围", selection: $exportAll) {
                        Text("当前页（\(files.count) 条）").tag(false)
                        Text("全部文件（\(runFileCount) 条）").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                Section("导出列") {
                    ForEach(allColumns, id: \.0) { col, label in
                        Toggle(label, isOn: Binding(
                            get: { exportColumns.contains(col) },
                            set: { on in
                                if on { exportColumns.insert(col) } else { exportColumns.remove(col) }
                            }
                        ))
                    }
                }
            }
            .navigationTitle("导出列表").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { showExportSheet = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("导出") {
                        var cols = exportColumns
                        if cols.isEmpty { cols = Set(allColumns.map { $0.0 }) }
                        let path = FileRepository.shared.exportLibraryText(
                            runId: runId, columns: cols, all: exportAll,
                            offset: page * pageSize, limit: pageSize,
                            currentPage: exportAll ? nil : files)
                        showExportSheet = false
                        if let p = path {
                            toast("已导出列表清单：\(p)")
                        } else {
                            toast("没有可导出的文件")
                        }
                    }
                }
            }
        }
    }

    // MARK: - 操作
    /// 轻提示（对齐安卓 Toast），2 秒后自动消失。
    private func toast(_ msg: String) {
        withAnimation { toastText = msg }
        let shown = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toastText == shown { withAnimation { toastText = nil } }
        }
    }

    private func updateFile(_ id: Int64, mutate: (inout ScannedFile) -> Void) {
        guard let i = files.firstIndex(where: { $0.id == id }) else { return }
        var arr = files
        mutate(&arr[i])
        files = arr
    }

    private func toggleCheck(_ f: ScannedFile) {
        let nv = f.checked == 1 ? 0 : 1
        updateFile(f.id) { $0.checked = nv }
        FileRepository.shared.setChecked(id: f.id, checked: nv == 1)
    }
    private func toggleMark(_ f: ScannedFile) {
        let nv = f.marked == 1 ? 0 : 1
        updateFile(f.id) { $0.marked = nv }
        FileRepository.shared.setMarked(id: f.id, marked: nv == 1)
    }
    private func toggleSelectAllPage() {
        selectAllOnPage.toggle()
        var arr = files
        for i in arr.indices { arr[i].checked = selectAllOnPage ? 1 : 0 }
        files = arr
        let ids = files.map { $0.id }
        FileRepository.shared.updateChecked(ids: ids, checked: selectAllOnPage)
    }

    // MARK: - 顶部汇总文案（对齐安卓 run_summary / group_summary / selected_count）
    private var summaryBar: some View {
        HStack(spacing: 6) {
            if mode == "group" {
                if checkedCount > 0 {
                    Text("共 \(groups.count) 个合集 · 已勾选 \(checkedCount)/\(totalCount) 个文件")
                        .fsFont(.caption).foregroundColor(.fsPrimary)
                } else {
                    Text("共 \(groups.count) 个合集 · \(totalCount) 个文件")
                        .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                }
            } else {
                if checkedCount > 0 {
                    Text("已勾选 \(checkedCount)/\(totalCount) 个文件")
                        .fsFont(.caption).foregroundColor(.fsPrimary)
                } else {
                    Text("共 \(totalCount) 个文件")
                        .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 步骤条点击处理
    private func handleStep(_ idx: Int) {
        switch idx {
        case 1:  // 合集
            if mode != "group" {
                mode = "group"
                UserDefaults.standard.set("group", forKey: "lib_mode")
                reload()
            }
        case 2:  // 勾选重复
            selectDuplicates()
        case 4:  // 删除
            if checkedCount > 0 {
                let ids = FileRepository.shared.getCheckedIds(runId: runId)
                guard !ids.isEmpty else { return }
                router.navigate(.deleteConfirm(runId: runId, ids: ids, physical: false))
            }
        default:
            break
        }
    }

    // 合集三态复选框：全部已勾选则取消该合集所有子文件，否则全选该合集所有子文件。
    private func toggleGroupChecked(title: String, author: String, allChecked: Bool) {
        let ids = DatabaseManager.shared.getGroupFiles(runId: runId, title: title, author: author).map { $0.id }
        guard !ids.isEmpty else { return }
        FileRepository.shared.updateChecked(ids: ids, checked: !allChecked)
        reload()
    }

    // 一键勾选重复：后台执行，避免大文库主线程阻塞；完成后刷新统计使步骤条前移到「确认/删除」。
    private func selectDuplicates() {
        running = true
        let rid = runId
        DispatchQueue.global(qos: .userInitiated).async {
            let dupIds = FileRepository.shared.selectDuplicateIds(runId: rid)
            DispatchQueue.main.async {
                running = false
                if dupIds.isEmpty {
                    toast("当前筛选下没有重复文件（按书名/作者）")
                } else {
                    reload()
                }
            }
        }
    }

    private func reload() {
        // 后台线程执行 DB 查询，避免大文库（十万级文件）在主线程 GROUP BY/COUNT 导致卡顿。
        let currentMode = mode
        let currentPage = page
        let currentPageSize = pageSize
        let curTitle = titleFilter, curAuthor = authorFilter, curProgress = progressFilter
        let curSource = sourceFilter, curSearch = search, curFilter = selectedFilter
        let curMin = prefs.groupMinCount, curMax = prefs.groupMaxCount
        let curExclude = LibraryLogic.parseExcludeNames(prefs.groupExcludeNames)
        let curGroupSort = prefs.groupSort
        let curCheckedFront = prefs.checkedSortToFront
        let curMarkedFront = prefs.markedSortToFront
        let repo = FileRepository.shared

        let (cf, mf): (Int, Int) = {
            switch curFilter {
            case "checked":   return (1, -1)
            case "unchecked": return (0, -1)
            case "marked":    return (-1, 1)
            case "unmarked":  return (-1, 0)
            default:          return (-1, -1)
            }
        }()

        DispatchQueue.global(qos: .userInitiated).async {
            if currentMode == "group" {
                let gTotal = repo.dbCountGroups(runId: runId, min: curMin, max: curMax, exclude: curExclude,
                                                checkedFilter: cf, markedFilter: mf)
                let gPageCount = LibraryLogic.computePageCount(total: max(gTotal, 1), pageSize: currentPageSize)
                let p = min(max(currentPage, 0), max(gPageCount - 1, 0))
                let gs = repo.dbPageGroups(runId: runId, min: curMin, max: curMax,
                                           exclude: curExclude, page: p, pageSize: currentPageSize,
                                           groupSort: curGroupSort, checkedSortToFront: curCheckedFront,
                                           checkedFilter: cf, markedFilter: mf)
                DispatchQueue.main.async {
                    groupTotal = gTotal; groupPageCount = gPageCount; page = p; groups = gs
                    let gc = repo.getGroupCheckedCounts(runId: runId)
                    groupChecked = gc
                    checkedCount = gc.values.reduce(0, +)
                    runFileCount = repo.dbCountFiles(runId: runId, title: "", author: "", progress: "", source: "", search: "", checkedFilter: -1, markedFilter: -1)
                    totalCount = runFileCount
                    selectAllOnPage = false
                }
                return
            }
            let t = repo.dbCountFiles(runId: runId, title: curTitle, author: curAuthor,
                                      progress: curProgress, source: curSource, search: curSearch,
                                      checkedFilter: cf, markedFilter: mf)
            let pc = LibraryLogic.computePageCount(total: max(t, 1), pageSize: currentPageSize)
            let p = min(max(currentPage, 0), max(pc - 1, 0))
            let fs = repo.dbPageFiles(runId: runId, page: p, pageSize: currentPageSize, sortBy: sortBy,
                                      ascending: ascending, title: curTitle, author: curAuthor,
                                      progress: curProgress, source: curSource, search: curSearch,
                                      checkedFilter: cf, markedFilter: mf,
                                      checkedSortToFront: curCheckedFront,
                                      markedSortToFront: curMarkedFront)
            DispatchQueue.main.async {
                total = t; pageCount = pc; page = p; files = fs
                checkedCount = repo.getCheckedCount(runId: runId)
                runFileCount = repo.dbCountFiles(runId: runId, title: "", author: "", progress: "", source: "", search: "", checkedFilter: -1, markedFilter: -1)
                totalCount = runFileCount
                selectAllOnPage = false
            }
        }
    }
}

extension FileRepository {
    func dbPageFiles(runId: Int64, page: Int, pageSize: Int, sortBy: String, ascending: Bool,
                     title: String, author: String, progress: String, source: String, search: String,
                     checkedFilter: Int = -1, markedFilter: Int = -1,
                     checkedSortToFront: Bool = false, markedSortToFront: Bool = false) -> [ScannedFile] {
        DatabaseManager.shared.getScannedFilesPaged(runId: runId, offset: page * pageSize, limit: pageSize,
                                                     sortBy: sortBy, ascending: ascending, titleFilter: title,
                                                     authorFilter: author, progressFilter: progress,
                                                     sourceFilter: source, search: search,
                                                     checkedFilter: checkedFilter, markedFilter: markedFilter,
                                                     checkedSortToFront: checkedSortToFront,
                                                     markedSortToFront: markedSortToFront)
    }
    func dbCountFiles(runId: Int64, title: String, author: String, progress: String, source: String, search: String,
                      checkedFilter: Int = -1, markedFilter: Int = -1) -> Int {
        DatabaseManager.shared.countScannedFiles(runId: runId, titleFilter: title, authorFilter: author,
                                                 progressFilter: progress, sourceFilter: source, search: search,
                                                 checkedFilter: checkedFilter, markedFilter: markedFilter)
    }
    func dbGroupFiles(runId: Int64, min: Int, max: Int, exclude: [String]) -> [NovelGroup] {
        DatabaseManager.shared.getNovelGroups(runId: runId, minCount: min, maxCount: max, excludeNames: exclude)
    }
    func dbCountGroups(runId: Int64, min: Int, max: Int, exclude: [String],
                        checkedFilter: Int = -1, markedFilter: Int = -1) -> Int {
        DatabaseManager.shared.countNovelGroups(runId: runId, minCount: min, maxCount: max, excludeNames: exclude,
                                                 checkedFilter: checkedFilter, markedFilter: markedFilter)
    }
    func dbPageGroups(runId: Int64, min: Int, max: Int, exclude: [String], page: Int, pageSize: Int,
                      groupSort: String = "count_desc", checkedSortToFront: Bool = false,
                      checkedFilter: Int = -1, markedFilter: Int = -1) -> [NovelGroup] {
        DatabaseManager.shared.getNovelGroupsPaged(runId: runId, minCount: min, maxCount: max,
                                                    excludeNames: exclude, offset: page * pageSize, limit: pageSize,
                                                    groupSort: groupSort, checkedSortToFront: checkedSortToFront,
                                                    checkedFilter: checkedFilter, markedFilter: markedFilter)
    }
}

// MARK: - 合集文件列表
struct GroupFilesView: View {
    @EnvironmentObject var router: Router
    let runId: Int64
    let title: String
    let author: String
    @State private var files: [ScannedFile] = []

    var body: some View {
        List {
            ForEach(files) { f in
                FileRow(
                    file: f,
                    onToggleCheck: { toggleCheck(f) },
                    onToggleMark: { toggleMark(f) },
                    onTap: { router.navigate(.fileDetail(id: f.id)) }
                )
            }
        }
        .listStyle(.plain)
        .navigationTitle("\(title.isEmpty ? "(无书名)" : title) / \(author.isEmpty ? "(无作者)" : author)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let rid = runId, t = title, a = author
            DispatchQueue.global(qos: .userInitiated).async {
                let data = DatabaseManager.shared.getGroupFiles(runId: rid, title: t, author: a)
                DispatchQueue.main.async { files = data }
            }
        }
    }

    private func updateFile(_ id: Int64, mutate: (inout ScannedFile) -> Void) {
        guard let i = files.firstIndex(where: { $0.id == id }) else { return }
        var arr = files
        mutate(&arr[i])
        files = arr
    }
    private func toggleCheck(_ f: ScannedFile) {
        let nv = f.checked == 1 ? 0 : 1
        updateFile(f.id) { $0.checked = nv }
        FileRepository.shared.setChecked(id: f.id, checked: nv == 1)
    }
    private func toggleMark(_ f: ScannedFile) {
        let nv = f.marked == 1 ? 0 : 1
        updateFile(f.id) { $0.marked = nv }
        FileRepository.shared.setMarked(id: f.id, marked: nv == 1)
    }
}

// MARK: - 文件详情
struct FileDetailView: View {
    @EnvironmentObject var router: Router
    let fileId: Int64
    @State private var file: ScannedFile?
    @State private var toastText: String? = nil

    /// 轻提示（本视图独立持有，LibraryView 的 toast 是其私有成员，此处访问不到）
    private func toast(_ msg: String) {
        withAnimation { toastText = msg }
        let shown = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toastText == shown { withAnimation { toastText = nil } }
        }
    }

    var body: some View {
        Group {
            if let f = file {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        detailInfoSection(f)
                        markRow(f)
                        checkRow(f)
                        DetailRow("内容哈希", f.contentHash.isEmpty ? "—" : f.contentHash, isMono: true)
                        DetailRow("路径", f.path.isEmpty ? "—" : FormatUtil.toHumanReadablePath(f.path), isPath: true)
                        actionSection(f)
                            .padding(.top, 8)
                    }
                    .padding(16)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("文件详情")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let t = toastText {
                Text(t)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(10)
                    .padding(.bottom, 40)
                    .transition(.opacity)
            }
        }
        .onAppear { file = FileRepository.shared.getById(fileId) }
    }

    @ViewBuilder
    private func detailInfoSection(_ f: ScannedFile) -> some View {
        DetailRow("书名", f.title.isEmpty ? "—" : "《\(f.title)》")
        DetailRow("作者", f.author.isEmpty ? "—" : f.author)
        DetailRow("原文件名", f.fileName)
        DetailRowColumns([
            ("扩展名", f.ext.isEmpty ? "—" : f.ext),
            ("大小", FormatUtil.formatSize(f.fileSize)),
            ("编码", f.encoding.isEmpty ? "—" : f.encoding)
        ])
        DetailRowColumns([
            ("进度", f.progress.isEmpty ? "—" : f.progress),
            ("来源", f.source.isEmpty ? "—" : f.source),
            ("日期", FormatUtil.formatFileDate(f.fileDate))
        ])
    }

    @ViewBuilder
    private func markRow(_ f: ScannedFile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: f.marked == 1 ? "star.fill" : "star")
                .foregroundColor(f.marked == 1 ? .orange : .fsSecondaryLabel)
            Text(f.marked == 1 ? "已标记" : "未标记")
                .fsFont(.subheadline).fontWeight(.medium)
            Spacer()
            Button {
                FileRepository.shared.setMarked(id: f.id, marked: f.marked != 1)
                file = FileRepository.shared.getById(f.id)
            } label: {
                Text(f.marked == 1 ? "取消标记" : "标记")
                    .fsFont(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.fsPrimary)
            }
        }
        .padding(12)
        .background(Color.fsSecondaryBg)
        .cornerRadius(10)
    }

    @ViewBuilder
    private func checkRow(_ f: ScannedFile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: f.checked == 1 ? "checkmark.circle.fill" : "circle")
                .foregroundColor(f.checked == 1 ? .fsPrimary : .fsSecondaryLabel)
            Text(f.checked == 1 ? "已勾选（将纳入清理清单）" : "未勾选")
                .fsFont(.subheadline).fontWeight(.medium)
            Spacer()
            Toggle("勾选删除", isOn: Binding(
                get: { f.checked == 1 },
                set: { nv in
                    FileRepository.shared.setChecked(id: f.id, checked: nv)
                    file = FileRepository.shared.getById(f.id)
                }
            ))
            .labelsHidden()
            .tint(.fsPrimary)
        }
        .padding(12)
        .background(Color.fsSecondaryBg)
        .cornerRadius(10)
    }

    @ViewBuilder
    private func actionSection(_ f: ScannedFile) -> some View {
        VStack(spacing: 12) {
            PrimaryButton(title: "预览内容") {
                router.navigate(.filePreview(id: f.id, mode: "head"))
            }
            Button {
                guard !f.path.isEmpty else {
                    toast("无法打开：文件路径为空"); return
                }
                guard let run = FileRepository.shared.getScanRun(f.scanRunId),
                      let resolved = resolveBookmarkURL(run.folderUri) else {
                    toast("无法打开：文件夹访问授权已失效，请重新扫描以刷新授权"); return
                }
                let folderURL = resolved.url
                // f.path 存的是 file:// 形式的绝对 URL 字符串，必须用 URL(string:) 解析，
                // 不能用 URL(fileURLWithPath:)（会把 "file:///..." 当成字面路径导致找不到文件）。
                guard let fileURL = URL(string: f.path) else {
                    toast("无法打开：文件路径无效"); return
                }
                // 安全作用域访问必须在主线程开启（针对扫描时授权的文件夹）
                let accessed = folderURL.startAccessingSecurityScopedResource()
                guard accessed, FileManager.default.fileExists(atPath: fileURL.path) else {
                    if accessed { folderURL.stopAccessingSecurityScopedResource() }
                    toast("无法打开：文件不存在或路径无效"); return
                }
                UIApplication.shared.open(fileURL) { success in
                    if accessed { folderURL.stopAccessingSecurityScopedResource() }
                    if !success { toast("没有可打开该文件的应用") }
                }
            } label: {
                Text("用其他应用打开").frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.fsTertiaryBg)
                    .foregroundColor(.fsPrimary)
                    .cornerRadius(10)
            }
            Button(role: .destructive) {
                // 跳转删除确认页，让用户选择「仅删除记录」或「记录与源文件一起删除」
                router.navigate(.deleteConfirm(runId: f.scanRunId, ids: [f.id], physical: false))
            } label: {
                Text("删除该文件").frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(.red)
                    .cornerRadius(10)
            }
        }
    }
}

// MARK: - 文件详情排布（对齐安卓/鸿蒙：卡片式信息行，标签在上 / 值在下）
private func DetailRow(_ label: String, _ value: String, isPath: Bool = false, isMono: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(label).fsFont(.caption).foregroundColor(.fsSecondaryLabel)
        Text(value)
            .fsFont(.subheadline, design: isMono ? .monospaced : .default)
            .fontWeight(.medium)
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(isPath ? 4 : nil)
            .textSelection(.enabled)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Color.fsSecondaryBg)
    .cornerRadius(10)
}

private func DetailRowColumns(_ items: [(String, String)]) -> some View {
    HStack(spacing: 0) {
        ForEach(items.indices, id: \.self) { i in
            VStack(alignment: .leading, spacing: 4) {
                Text(items[i].0).fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                Text(items[i].1).fsFont(.subheadline).fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if i < items.count - 1 {
                Divider().frame(height: 36).padding(.horizontal, 8)
            }
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Color.fsSecondaryBg)
    .cornerRadius(10)
}

// MARK: - 文件预览（阅读，对齐安卓）
struct FilePreviewView: View {
    let fileId: Int64
    let mode: String
    @EnvironmentObject var prefs: Preferences
    @State private var text = "加载中…"
    @State private var totalLines = 0
    @State private var modeState: String
    @State private var fontPt: CGFloat = 16
    @StateObject private var scrollState = PreviewScrollState()
    @State private var file: ScannedFile?
    @State private var uiKitReady = false

    init(fileId: Int64, mode: String) {
        self.fileId = fileId
        self.mode = mode
        self._modeState = State(initialValue: mode)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 信息栏 + 字号调节（对齐安卓底部信息栏：字号 / 编码 / 已加载行数）
            HStack(spacing: 12) {
                Button { if fontPt > 10 { fontPt -= 1 } } label: {
                    Image(systemName: "textformat.size.smaller")
                        .font(.system(size: 15, weight: .medium))
                }
                Text("\(Int(fontPt))")
                    .frame(minWidth: 28).multilineTextAlignment(.center)
                    .fsFont(.caption)
                Button { if fontPt < 30 { fontPt += 1 } } label: {
                    Image(systemName: "textformat.size.larger")
                        .font(.system(size: 15, weight: .medium))
                }
                Divider().frame(height: 20)
                Text("编码: \(file?.encoding.isEmpty ?? true ? "UTF-8" : (file?.encoding ?? "UTF-8"))")
                    .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                Spacer()
                Text("已加载 \(totalLines) 行").fsFont(.caption).foregroundColor(.fsSecondaryLabel)
            }
            .frame(height: 44, alignment: .center)
            .padding(.horizontal, 12)
            .background(Color.fsSecondaryBg)

            // 文本 + 自定义滑条（统一纵向滚动条）
            ZStack(alignment: .topTrailing) {
                if uiKitReady {
                    ScrollableText(text: text, fontPt: fontPt,
                                   mode: .vertical,
                                   allLines: nil,
                                   state: scrollState)
                    // UIScrollView 作为 SwiftUI 子视图没有固有高度，必须显式撑满父级剩余空间，
                    // 否则 scroll.bounds.height=0，updateUIView 拿不到可视区域，文本永远无法渲染（屏幕全黑）。
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    MiniScrollBar(state: scrollState,
                                  axis: .vertical)
                } else {
                    Text("加载中…").foregroundColor(.fsSecondaryLabel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .navigationTitle(file?.fileName ?? "预览")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            FileRepository.shared.logOperation(level: "I", tag: "预览", message: "进入预览页 id=\(fileId) mode=\(modeState)")
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { if modeState != "head" { modeState = "head"; Task { await load() } } } label: { Label("前 50 行", systemImage: modeState == "head" ? "checkmark" : "text.line.first") }
                    Button { if modeState != "tail" { modeState = "tail"; Task { await load() } } } label: { Label("后 100 行", systemImage: modeState == "tail" ? "checkmark" : "text.line.last") }
                    Button { if modeState != "all" { modeState = "all"; Task { await load() } } } label: { Label("全部内容", systemImage: modeState == "all" ? "checkmark" : "doc.plaintext") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task { await load() }
    }

    private func load() async {
        FileRepository.shared.logOperation(level: "I", tag: "预览", message: "load() 开始 id=\(fileId)")
        let m = modeState
        // 关键：getById / getScanRun / resolveBookmarkURL(URL(resolvingBookmarkData:)) 在文件位于
        // File Provider / 外部文件夹时，会在主线程同步跨进程请求文件提供程序扩展，可能卡数秒，
        // 直接触发 watchdog（0x8BADF00D）强杀。所以整段预备 + 读取 + 安全作用域 start/stop
        // 全部放到 detached 后台线程执行，主线程只负责 UI 赋值。
        // 注意：start/stopAccessingSecurityScopedResource 并不要求主线程，任意线程配对即可。
        let (fid, mmode) = (fileId, m)
        let result = await Task.detached(priority: .userInitiated) { () -> (String, String?, Int, ScannedFile?) in
            guard let f = FileRepository.shared.getById(fid) else {
                FileRepository.shared.logOperation(level: "E", tag: "预览", message: "文件不存在 id=\(fid)")
                return ("文件不存在", nil, 0, nil)
            }
            FileRepository.shared.logOperation(level: "I", tag: "预览", message: "取到文件 \(f.fileName) encoding=\(f.encoding) size=\(f.fileSize)")
            guard let run = FileRepository.shared.getScanRun(f.scanRunId),
                  let resolved = resolveBookmarkURL(run.folderUri) else {
                FileRepository.shared.logOperation(level: "E", tag: "预览", message: "文件夹授权失效 id=\(fid)")
                return ("无法访问文件夹（授权失效），请重新扫描以刷新授权", nil, 0, f)
            }
            let accessed = resolved.url.startAccessingSecurityScopedResource()
            if !accessed {
                FileRepository.shared.logOperation(level: "E", tag: "预览", message: "无法开启文件夹访问权限 id=\(fid)")
                return ("无法访问文件夹（权限被拒绝），请重新扫描并授权", nil, 0, f)
            }
            defer { resolved.url.stopAccessingSecurityScopedResource() }
            let r = FilePreviewView.readFileContent(f, mode: mmode)
            return (r.0, r.1, r.2, f)
        }.value
        // 页面可能已被切换/返回，重入的旧任务不应覆盖新内容
        guard fileId == fid, modeState == mmode else {
            FileRepository.shared.logOperation(level: "W", tag: "预览", message: "load() 页面已切换，丢弃旧结果 id=\(fileId)")
            return
        }
        file = result.3
        let shown = result.1 ?? result.0
        text = shown
        totalLines = result.2
        if let hint = result.1 {
            FileRepository.shared.logOperation(level: "E", tag: "预览", message: "读取失败 id=\(fileId) hint=\(hint)")
        } else {
            FileRepository.shared.logOperation(level: "I", tag: "预览", message: "拿到文本 len=\(shown.count) lines≈\(result.2) 准备挂载 UIKit")
        }
        uiKitReady = true
    }

    /// 读取文件预览内容。优先使用扫描时保存的文件夹安全作用域书签；若书签失效，则尝试直接读取文件 URL（部分场景可访问）。
    /// 返回 (content, errorHint, lineCount) 元组；errorHint 为 nil 表示成功，非 nil 时应显示该提示。
    /// 声明为 `nonisolated static`，确保可在后台线程调用，不隐式跳回主 actor。
    nonisolated static func readFileContent(_ f: ScannedFile, mode: String) -> (String, String?, Int) {
        let tag = "FilePreview"
        FileRepository.shared.logOperation(level: "D", tag: "预览读取", message: "readFileContent 开始 id=\(f.id) mode=\(mode) path=\(f.path)")
        // f.path 是 file:// 形式的绝对 URL 字符串，必须用 URL(string:) 解析
        guard let url = URL(string: f.path) else {
            FileRepository.shared.logOperation(level: "E", tag: "预览读取", message: "文件路径无效 \(f.path)")
            LogUtil.e(tag, "invalid file path: \(f.path)")
            return ("", "文件路径无效：\(f.path)", 0)
        }

        // 检查文件是否存在（安全作用域已由 load() 的 detached 后台任务开启）
        FileRepository.shared.logOperation(level: "D", tag: "预览读取", message: "检查文件存在性 path=\(url.path)")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ("", "文件不存在或已被移动：\(url.lastPathComponent)", 0)
        }

        let enc = f.encoding.isEmpty ? "UTF-8" : f.encoding
        // 按模式收敛读取量：菜单里 head=「前 50 行」、tail=「后 100 行」，
        // 原先一律读 200KB 再全量解码+排版，是预览慢的直接原因。
        // 50/100 行中文约 4~12KB，这里给足 64KB 余量即可，仅 all 模式才读满 200KB。
        let maxBytes = (mode == "all") ? 200 * 1024 : 64 * 1024

        // 编码尝试链（去重保序）：
        //   1) 扫描阶段记录的存储编码（早期可能误判为 UTF-8）
        //   2) GB18030（中文 txt 最常见的编码，优先于 UTF-8 兜底，避免 UTF-8 静默丢字节乱码）
        //   3) UTF-8
        // 使用 EncodingUtil.decodeStrict：以「CJK 内容占比」为核心判据选择最合理解码；
        // 真 UTF-8 字节流因其 CJK 占比高且通过 looksLikeUtf8 校验而带红利，仍会被优先选中。
        // 覆盖典型场景：扫描仅采样 8KB，文件前段是 ASCII 序章被判为 UTF-8，
        // 中文内容出现在样本外，预览时整文件按错误编码解码会乱码——此处自动校正。
        var candidates: [String] = []
        for name in [enc, "GB18030", "UTF-8"] where !candidates.contains(name) {
            candidates.append(name)
        }

        // 先尝试 FileHandle（可控偏移，支持 tail 模式）；失败则回退到 Data(contentsOf:)。
        if let data = readFileData(url: url, mode: mode, maxBytes: maxBytes, tag: tag) {
            let truncatedSuffix = makeTruncatedSuffix(mode: mode, dataCount: data.count, maxBytes: maxBytes)
            var (text, usedName) = EncodingUtil.decodeStrict(data: data, candidates: candidates)
            if !text.isEmpty {
                if usedName != enc {
                    FileRepository.shared.logOperation(level: "W", tag: "预览读取", message: "编码回退 stored=\(enc) used=\(usedName) file=\(url.lastPathComponent)")
                    LogUtil.d(tag, "preview fallback decoding: \(url.lastPathComponent) stored=\(enc) used=\(usedName)")
                }
                // 换行规整：文件可能含 Windows 换行 \r\n 或经典 Mac \r，统一为 \n，
                // 避免 TextKit 多算行高、纵向滚动条比例失真。
                text = text.replacingOccurrences(of: "\r\n", with: "\n")
                           .replacingOccurrences(of: "\r", with: "\n")

                // 按模式裁到实际需要的行数（head=前 50 行、tail=后 100 行），
                // 与菜单文案保持一致，同时把送进 UITextView 的文本量降到最低。
                var lineNote = ""
                if mode == "head" || mode == "tail" {
                    let want = (mode == "head") ? 50 : 100
                    var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                    if lines.count > want {
                        lines = (mode == "head") ? Array(lines.prefix(want)) : Array(lines.suffix(want))
                        lineNote = (mode == "head")
                            ? "\n\n…（仅显示前 \(want) 行，切换「全部内容」查看更多）"
                            : "\n\n…（仅显示后 \(want) 行，切换「全部内容」查看更多）"
                    }
                    text = lines.joined(separator: "\n")
                } else {
                    // 仅「全部内容」模式可能达到十万字级，需做硬上限保护，
                    // 避免 UITextView 排版/内存激增导致主线程卡死或闪退。
                    let hardLimit = 120_000 // 字符数上限，约等于 200KB 中文的可视量
                    if text.count > hardLimit {
                        text = String(text.prefix(hardLimit))
                        lineNote = "\n\n…（内容过长，预览已截断）"
                        FileRepository.shared.logOperation(level: "W", tag: "预览读取", message: "触发硬上限 120000 字符 file=\(url.lastPathComponent)")
                    }
                }

                // head/tail 已自带行数说明，就不再重复贴字节截断说明
                let suffix = lineNote.isEmpty ? truncatedSuffix : lineNote
                let full = text + suffix
                // 行数在后台一并算好，避免主线程再对大字符串 split 一次
                let lineCount = full.reduce(into: 1) { acc, ch in if ch == "\n" { acc += 1 } }
                return (full, nil, lineCount)
            }
            FileRepository.shared.logOperation(level: "E", tag: "预览读取", message: "解码失败 tried=\(candidates.joined(separator: "/")) file=\(url.lastPathComponent)")
            LogUtil.e(tag, "string decoding failed for \(url.lastPathComponent), tried=\(candidates.joined(separator: ","))")
            return ("", "文件编码解析失败（已尝试 \(candidates.joined(separator: "/"))，均解码失败）", 0)
        }
        FileRepository.shared.logOperation(level: "E", tag: "预览读取", message: "读数据失败（权限/IO）file=\(url.lastPathComponent)")
        return ("", "无法读取文件数据（可能缺少文件夹访问权限，请重新扫描以刷新授权）", 0)
    }

    nonisolated private static func readFileData(url: URL, mode: String, maxBytes: Int, tag: String) -> Data? {
        // 读取策略（针对 File Provider / 外部文件夹）：
        // File Provider 扩展未运行时，NSFileCoordinator.coordinate 会**同步阻塞**当前线程等待扩展响应，
        // 扩展被强杀/未启动时会直接触发 Data.subscript 越界 trap（EXC_BREAKPOINT）导致闪退。
        // 因此优先用「直接 FileHandle / Data(contentsOf:)」读取——在已 startAccessingSecurityScopedResource
        // 的授权前提下，File Provider 已落盘的文件通常可直接读，无需 coordinator 介入。
        let readRange: Range<Int> = (mode == "tail")
            ? (0..<maxBytes)   // 末尾：先全取，后截
            : (0..<maxBytes)

        func slice(_ data: Data) -> Data {
            guard !data.isEmpty else { return data }
            if mode == "tail" {
                // Swift Int 减法下溢会 trap；当 data.count < maxBytes 时直接用 0。
                let offset = data.count > maxBytes ? data.count - maxBytes : 0
                return data.subdata(in: offset..<data.count)
            } else {
                return data.count > maxBytes ? data.subdata(in: 0..<maxBytes) : data
            }
        }

        // 1) 直接读（最快、最稳，适用于已授权可读的文件）
        if let fh = try? FileHandle(forReadingFrom: url) {
            defer { try? fh.close() }
            if mode == "tail" {
                let total = (try? fh.seekToEnd()) ?? 0
                let from = max(0, Int(total) - maxBytes)
                fh.seek(toFileOffset: UInt64(from))
                if let d = try? fh.readData(ofLength: maxBytes), !d.isEmpty {
                    return slice(d)
                }
            } else {
                fh.seek(toFileOffset: 0)
                if let d = try? fh.readData(ofLength: maxBytes), !d.isEmpty {
                    return d
                }
            }
        }
        if let d = try? Data(contentsOf: url), !d.isEmpty {
            return slice(d)
        }

        // 2) 兜底：NSFileCoordinator（仅在直接读失败时尝试，用于极端场景）
        var result: Data?
        var coordError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordError) { coordinatedURL in
            if let fh = try? FileHandle(forReadingFrom: coordinatedURL) {
                defer { try? fh.close() }
                let total = (try? fh.seekToEnd()) ?? 0
                let from = max(0, Int(total) - maxBytes)
                fh.seek(toFileOffset: UInt64(from))
                result = try? fh.readData(ofLength: maxBytes)
            } else {
                result = try? Data(contentsOf: coordinatedURL)
            }
        }
        if let err = coordError {
            FileRepository.shared.logOperation(level: "E", tag: "预览读取", message: "NSFileCoordinator 错误 file=\(url.lastPathComponent) err=\(err.localizedDescription)")
            LogUtil.e(tag, "NSFileCoordinator error for \(url.lastPathComponent): \(err)")
        }
        guard let data = result, !data.isEmpty else {
            FileRepository.shared.logOperation(level: "E", tag: "预览读取", message: "读数据失败（权限/IO）file=\(url.lastPathComponent)")
            LogUtil.e(tag, "readFileData failed for \(url.lastPathComponent)")
            return nil
        }
        return slice(data)
    }

    nonisolated private static func makeTruncatedSuffix(mode: String, dataCount: Int, maxBytes: Int) -> String {
        if mode == "tail" {
            return dataCount >= maxBytes ? "\n\n…（预览仅显示末尾 \(maxBytes / 1024) KB，完整内容请在原文件查看）" : ""
        } else {
            return dataCount >= maxBytes ? "\n\n…（预览仅显示前 \(maxBytes / 1024) KB，完整内容请在原文件查看）" : ""
        }
    }
}

// MARK: - 可滚动文本（UIKit 封装，支持横/竖自定义滑条，对齐安卓滑条行为）
enum ScrollMode { case vertical, horizontal }

/// 桥接 UIScrollView 的滚动状态，供 SwiftUI 绘制滑条并反向控制。
final class PreviewScrollState: ObservableObject {
    @Published var contentSize: CGSize = .zero
    @Published var viewport: CGSize = .zero
    @Published var offset: CGPoint = .zero
    weak var scrollView: UIScrollView?

    var maxOffsetX: CGFloat { max(0, contentSize.width - viewport.width) }
    var maxOffsetY: CGFloat { max(0, contentSize.height - viewport.height) }

    func scrollTo(ratio: CGFloat, axis: ScrollMode) {
        guard let sv = scrollView else { return }
        let r = min(max(ratio, 0), 1)
        if axis == .vertical {
            sv.contentOffset.y = r * maxOffsetY
        } else {
            sv.contentOffset.x = r * maxOffsetX
        }
    }
}

struct ScrollableText: UIViewRepresentable {
    let text: String
    let fontPt: CGFloat
    let mode: ScrollMode
    let allLines: Set<Int>?
    let state: PreviewScrollState

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.backgroundColor = .systemBackground
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.isDirectionalLockEnabled = (mode == .horizontal)
        scroll.delegate = context.coordinator
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        // 关键：关闭内层 UITextView 自滚动，由外层 UIScrollView 完全控制滚动并测量 contentSize。
        // 同时采用手动 frame 布局（保持 translatesAutoresizingMaskIntoConstraints=默认 true），
        // 避免 SwiftUI 首次 layout 时 scroll.bounds=0 导致 AutoLayout 解析异常、tv 宽度/高度为 0、文本完全不可见。
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        scroll.addSubview(tv)
        context.coordinator.state = state
        context.coordinator.scroll = scroll
        context.coordinator.textView = tv
        state.scrollView = scroll
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        // 视图已卸载（返回上个页面 / 切换文件）：context 可能已失效，立即退出，避免访问
        // 已离屏或重用的 scrollView/UITextView 造成 EXC_BAD_ACCESS。
        // 典型场景：第一个文件 bounds=0 时排了 DispatchQueue.main.async 重入闭包，用户在
        // 下一帧前返回并打开第二个文件，旧闭包 fire 时访问已释放的 context/scroll 导致闪退。
        let coord = context.coordinator
        guard !coord.cancelled, coord.textView != nil else { return }
        // SwiftUI 首次 layout 时 scroll.bounds 可能仍为 0，延迟到下一帧再渲染，避免首帧 tv 宽度为 0 文本不可见。
        if scroll.bounds.width <= 0 || scroll.bounds.height <= 0 {
            // 文本待渲染但 scroll 尚未 layout：调度到下一个 runloop，等 SwiftUI 完成 layout 后重试。
            // 注意：闭包**绝不能捕获 context**（Context 内含 SwiftUI 内部存储，视图卸载后再访问其
            // coordinator 会 EXC_BAD_ACCESS）。这里只捕获 weak scroll + 强引用 coordinator 对象本身。
            // 同时限制重试次数，防止 bounds 长期为 0 时无限递归排队把主线程打爆。
            if coord.lastText != text && coord.layoutRetry < 30 {
                coord.layoutRetry += 1
                let pending = text
                let pendingFont = fontPt
                let pendingMode = mode
                DispatchQueue.main.async { [weak scroll, weak coord] in
                    guard let scroll = scroll, let coord = coord, !coord.cancelled else { return }
                    ScrollableText.applyLayout(scroll: scroll, coord: coord,
                                               text: pending, fontPt: pendingFont, mode: pendingMode)
                }
            }
            return
        }
        coord.layoutRetry = 0
        ScrollableText.applyLayout(scroll: scroll, coord: coord, text: text, fontPt: fontPt, mode: mode)
    }

    /// 实际排版逻辑，脱离 `Context` 独立执行，便于异步重试时安全调用。
    private static func applyLayout(scroll: UIScrollView, coord: Coordinator,
                                    text: String, fontPt: CGFloat, mode: ScrollMode) {
        guard !coord.cancelled, let tv = coord.textView else { return }
        if scroll.bounds.width <= 0 || scroll.bounds.height <= 0 {
            guard coord.layoutRetry < 30 else { return }
            coord.layoutRetry += 1
            DispatchQueue.main.async { [weak scroll, weak coord] in
                guard let scroll = scroll, let coord = coord, !coord.cancelled else { return }
                ScrollableText.applyLayout(scroll: scroll, coord: coord, text: text, fontPt: fontPt, mode: mode)
            }
            return
        }
        coord.layoutRetry = 0
        applyText(tv: tv, scroll: scroll, coord: coord, text: text, fontPt: fontPt, mode: mode)
        coord.publish(scroll)
    }

    private static func applyText(tv: UITextView, scroll: UIScrollView, coord: Coordinator,
                                  text: String, fontPt: CGFloat, mode: ScrollMode) {
        // 文本或字号未变化时跳过重设富文本与布局，避免每次 body 重算都同步重建大段 NSAttributedString 阻塞主线程。
        guard coord.lastText != text || coord.lastFontPt != fontPt else { return }
        coord.lastText = text
        coord.lastFontPt = fontPt
        let font = UIFont.systemFont(ofSize: fontPt)
        tv.font = font
        tv.textColor = .label
        // 用 plain text + font 而非 NSAttributedString：后者对十万字级文本要额外构建属性串，
        // 主线程耗时显著且内存翻倍，是大文件预览卡顿/被系统杀掉的诱因之一。
        tv.text = text
        let inset: CGFloat = 12
        let viewportW = max(1, scroll.bounds.width - inset * 2)
        let viewportH = max(1, scroll.bounds.height - inset * 2)
        if mode == .horizontal {
            // 横向：高度固定为视口高度，宽度随内容自然展开。
            // 不使用 sizeToFit()（会对全文做无限宽排版，超大文本极易卡死），
            // 改用 TextKit 按需测量并对宽度设上限。
            tv.textContainer.size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: viewportH)
            tv.textContainer.lineBreakMode = .byClipping
            let measured = tv.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: viewportH))
            let w = min(max(measured.width, viewportW), 20_000) // 上限防止 contentSize 溢出导致渲染异常
            tv.frame = CGRect(x: inset, y: inset, width: w, height: viewportH)
            scroll.contentSize = CGSize(width: w + inset * 2, height: scroll.bounds.height)
        } else {
            // 纵向：宽度固定为视口宽度。
            // 不用 sizeThatFits 全量排版（12 万字符的 UITextView 一次性排版耗时百毫秒级、易卡主线程），
            // 改用「行数 × 行高」估算内容高度——行高由字号决定、与内容无关，估算误差极小且瞬时完成。
            tv.textContainer.size = CGSize(width: viewportW, height: CGFloat.greatestFiniteMagnitude)
            tv.textContainer.lineBreakMode = .byWordWrapping
            tv.frame = CGRect(x: inset, y: inset, width: viewportW, height: viewportH)
            let lineHeight = font.lineHeight
            let lineCount = max(text.isEmpty ? 1 : text.reduce(into: 1) { acc, ch in if ch == "\n" { acc += 1 } },
                                Int((viewportH / max(lineHeight, 1)).rounded(.up)))
            let h = CGFloat(lineCount) * lineHeight
            scroll.contentSize = CGSize(width: scroll.bounds.width, height: h + inset * 2)
        }
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator()
        return c
    }

    /// 视图从层级移除时 SwiftUI 调用：标记 coordinator 已取消，
    /// 使早先排队的 DispatchQueue.main.async 重入闭包（来自 bounds=0 的首帧）安全退出，
    /// 不再访问即将释放的 scrollView/UITextView，修复「预览第一个文件返回后开第二个文件闪退」。
    static func dismantleUIView(_ scroll: UIScrollView, coordinator: Coordinator) {
        coordinator.cancelled = true
        coordinator.textView = nil
        coordinator.scroll = nil
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        weak var state: PreviewScrollState?
        weak var scroll: UIScrollView?
        weak var textView: UITextView?
        var lastText: String?
        var lastFontPt: CGFloat = 0
        /// 视图已卸载标记：FilePreviewView 的 .onDisappear 会置 true，
        /// 此后所有异步重入的 updateUIView 闭包立即退出，不再访问已离屏的 scrollView，
        /// 避免「第一个文件预览返回后又开第二个文件」时旧闭包导致的 EXC_BAD_ACCESS 闪退。
        var cancelled = false
        /// bounds 尚未 layout 时的重试计数，超过上限即放弃，防止无限递归排队卡死主线程。
        var layoutRetry = 0

        func publish(_ scroll: UIScrollView) {
            state?.contentSize = scroll.contentSize
            state?.viewport = scroll.bounds.size
            state?.offset = scroll.contentOffset
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            state?.contentSize = scrollView.contentSize
            state?.viewport = scrollView.bounds.size
            state?.offset = scrollView.contentOffset
        }
    }
}

// MARK: - 自定义滑条（竖：右侧；横：底部，对齐安卓滑条位置）
struct MiniScrollBar: View {
    @ObservedObject var state: PreviewScrollState
    let axis: ScrollMode

    var body: some View {
        GeometryReader { geo in
            let maxOff = axis == .vertical ? state.maxOffsetY : state.maxOffsetX
            let viewLen = axis == .vertical ? geo.size.height : geo.size.width
            let contentLen = axis == .vertical ? state.contentSize.height : state.contentSize.width
            let ratio = maxOff > 0 ? (axis == .vertical ? state.offset.y : state.offset.x) / maxOff : 0
            let thumbLen = max(28, viewLen * (viewLen / max(contentLen, 1)))
            let maxPos = max(0, viewLen - thumbLen)
            let thumbPos = CGFloat(ratio) * maxPos
            ZStack {
                if axis == .vertical {
                    Color.gray.opacity(0.25)
                        .frame(width: 4, height: viewLen)
                        .cornerRadius(2)
                        .position(x: geo.size.width - 2, y: viewLen / 2)
                    Color.gray.opacity(0.7)
                        .frame(width: 4, height: thumbLen)
                        .cornerRadius(2)
                        .position(x: geo.size.width - 2, y: thumbPos + thumbLen / 2)
                        .gesture(DragGesture().onChanged { v in
                            let p = min(max(v.location.y - thumbLen / 2, 0), maxPos)
                            state.scrollTo(ratio: maxPos > 0 ? p / maxPos : 0, axis: .vertical)
                        })
                } else {
                    Color.gray.opacity(0.25)
                        .frame(width: viewLen, height: 4)
                        .cornerRadius(2)
                        .position(x: viewLen / 2, y: geo.size.height - 2)
                    Color.gray.opacity(0.7)
                        .frame(width: thumbLen, height: 4)
                        .cornerRadius(2)
                        .position(x: thumbPos + thumbLen / 2, y: geo.size.height - 2)
                        .gesture(DragGesture().onChanged { v in
                            let p = min(max(v.location.x - thumbLen / 2, 0), maxPos)
                            state.scrollTo(ratio: maxPos > 0 ? p / maxPos : 0, axis: .horizontal)
                        })
                }
            }
        }
    }
}
