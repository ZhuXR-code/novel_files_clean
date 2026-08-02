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
    @State private var selectedGroup: NovelGroup?
    @State private var selectedFilter = "all"     // all/checked/unchecked/marked/unmarked
    @State private var autoCollapse = false
    @State private var showGroupSettings = false
    @State private var showDeleteConfirm = false
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
        .onChange(of: selectedFilter) { _ in reload() }
        .onAppear { reload() }
        .sheet(isPresented: $showFilter) { filterSheet }
        .sheet(isPresented: $showGroupSettings) { groupSettingsSheet }
        .sheet(isPresented: $showExportSheet) { exportSheet }
        .sheet(item: $selectedGroup) { g in
            NavigationStack {
                GroupFilesView(runId: runId, title: g.title == "(无书名)" ? "" : g.title, author: g.author)
                    .navigationTitle("\(g.title) / \(g.author)")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { selectedGroup = nil } } }
            }
        }
        .alert("删除勾选文件", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                let ids = FileRepository.shared.getCheckedIds(runId: runId)
                guard !ids.isEmpty else { return }
                FileRepository.shared.deleteFiles(ids: ids)
                reload()
            }
        } message: {
            Text("将删除所有已勾选的文件，且无法恢复。确定继续？")
        }
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
                        .onTapGesture { selectedGroup = g }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var toolbarItems: some ToolbarContent {
        Group {
            // 常驻操作（对齐安卓文库顶部图标栏：勾选重复 / 删除选中 / 更多）
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    selectDuplicates()
                } label: { Image(systemName: "checkmark.circle") }
                .help("一键勾选重复")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    let ids = FileRepository.shared.getCheckedIds(runId: runId)
                    guard !ids.isEmpty else { return }
                    showDeleteConfirm = true
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

                    Divider()
                    // 批量操作（对齐安卓文库「更多」菜单）
                    Menu("批量操作") {
                        Button("标记重复文件名") {
                            let n = FileRepository.shared.markDuplicatesByFileName(runId: runId)
                            toast("已标记 \(n) 个同名重复文件")
                            reload()
                        }
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
                    Button("一键清理") { router.navigate(.oneClick(runId: runId)) }
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
                            offset: page * pageSize, limit: pageSize)
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
            if checkedCount > 0 { showDeleteConfirm = true }
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
            FileRepository.shared.selectDuplicateIds(runId: rid)
            DispatchQueue.main.async {
                running = false
                reload()
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
        let repo = FileRepository.shared

        DispatchQueue.global(qos: .userInitiated).async {
            if currentMode == "group" {
                let gTotal = repo.dbCountGroups(runId: runId, min: curMin, max: curMax, exclude: curExclude)
                let gPageCount = LibraryLogic.computePageCount(total: max(gTotal, 1), pageSize: currentPageSize)
                let p = min(max(currentPage, 0), max(gPageCount - 1, 0))
                let gs = repo.dbPageGroups(runId: runId, min: curMin, max: curMax,
                                           exclude: curExclude, page: p, pageSize: currentPageSize,
                                           groupSort: curGroupSort, checkedSortToFront: curCheckedFront)
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
            let (cf, mf): (Int, Int) = {
                switch curFilter {
                case "checked":   return (1, -1)
                case "unchecked": return (0, -1)
                case "marked":    return (-1, 1)
                case "unmarked":  return (-1, 0)
                default:          return (-1, -1)
                }
            }()
            let t = repo.dbCountFiles(runId: runId, title: curTitle, author: curAuthor,
                                      progress: curProgress, source: curSource, search: curSearch,
                                      checkedFilter: cf, markedFilter: mf)
            let pc = LibraryLogic.computePageCount(total: max(t, 1), pageSize: currentPageSize)
            let p = min(max(currentPage, 0), max(pc - 1, 0))
            let fs = repo.dbPageFiles(runId: runId, page: p, pageSize: currentPageSize, sortBy: sortBy,
                                      ascending: ascending, title: curTitle, author: curAuthor,
                                      progress: curProgress, source: curSource, search: curSearch,
                                      checkedFilter: cf, markedFilter: mf,
                                      checkedSortToFront: curCheckedFront)
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
                     checkedSortToFront: Bool = false) -> [ScannedFile] {
        DatabaseManager.shared.getScannedFilesPaged(runId: runId, offset: page * pageSize, limit: pageSize,
                                                     sortBy: sortBy, ascending: ascending, titleFilter: title,
                                                     authorFilter: author, progressFilter: progress,
                                                     sourceFilter: source, search: search,
                                                     checkedFilter: checkedFilter, markedFilter: markedFilter,
                                                     checkedSortToFront: checkedSortToFront)
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
    func dbCountGroups(runId: Int64, min: Int, max: Int, exclude: [String]) -> Int {
        DatabaseManager.shared.countNovelGroups(runId: runId, minCount: min, maxCount: max, excludeNames: exclude)
    }
    func dbPageGroups(runId: Int64, min: Int, max: Int, exclude: [String], page: Int, pageSize: Int,
                      groupSort: String = "count_desc", checkedSortToFront: Bool = false) -> [NovelGroup] {
        DatabaseManager.shared.getNovelGroupsPaged(runId: runId, minCount: min, maxCount: max,
                                                    excludeNames: exclude, offset: page * pageSize, limit: pageSize,
                                                    groupSort: groupSort, checkedSortToFront: checkedSortToFront)
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
    @State private var fileToDelete: ScannedFile? = nil
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
                    VStack(alignment: .leading, spacing: 0) {
                        // 单列行（标签在上 / 值在下 / 分隔线）
                        DetailRow("书名", f.title.isEmpty ? "—" : "《\(f.title)》")
                        DetailRow("作者", f.author.isEmpty ? "—" : f.author)
                        DetailRow("原文件名", f.fileName)

                        // 一行多列：扩展名 | 大小 | 编码
                        DetailRowColumns([
                            ("扩展名", f.ext.isEmpty ? "—" : f.ext),
                            ("大小", FormatUtil.formatSize(f.fileSize)),
                            ("编码", f.encoding.isEmpty ? "—" : f.encoding)
                        ])
                        // 一行多列：进度 | 来源 | 日期
                        DetailRowColumns([
                            ("进度", f.progress.isEmpty ? "—" : f.progress),
                            ("来源", f.source.isEmpty ? "—" : f.source),
                            ("日期", FormatUtil.formatFileDate(f.fileDate))
                        ])
                        // 一行多列：已标记 | 已勾选
                        DetailRowColumns([
                            ("已标记", f.marked == 1 ? "已标记" : "未标记"),
                            ("已勾选", f.checked == 1 ? "已勾选" : "未勾选")
                        ])

                        // 单列行：内容哈希 / 路径
                        DetailRow("内容哈希", f.contentHash.isEmpty ? "—" : f.contentHash, isMono: true)
                        DetailRow("路径", f.path.isEmpty ? "—" : FormatUtil.toHumanReadablePath(f.path), isPath: true)

                        // 操作按钮（对齐安卓：预览 / 用其他应用打开 / 标记 / 删除）
                        VStack(spacing: 12) {
                            PrimaryButton(title: "预览内容") {
                                router.navigate(.filePreview(id: f.id, mode: "head"))
                            }
                            Button {
                                guard !f.path.isEmpty else {
                                    toast("无法打开：文件路径为空"); return
                                }
                                guard let run = FileRepository.shared.getScanRun(f.scanRunId),
                                      let folderURL = resolveBookmarkURL(run.folderUri) else {
                                    toast("无法打开：文件夹访问授权已失效，请重新扫描以刷新授权"); return
                                }
                                // 安全作用域访问必须在主线程开启，文件 URL 用 fileURLWithPath 构造
                                let accessed = folderURL.startAccessingSecurityScopedResource()
                                let url = URL(fileURLWithPath: f.path)
                                guard accessed, FileManager.default.fileExists(atPath: f.path) else {
                                    if accessed { folderURL.stopAccessingSecurityScopedResource() }
                                    toast("无法打开：文件不存在或路径无效"); return
                                }
                                UIApplication.shared.open(url) { success in
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
                            Button {
                                FileRepository.shared.setMarked(id: f.id, marked: f.marked != 1)
                                file = FileRepository.shared.getById(f.id)
                            } label: {
                                Text(f.marked == 1 ? "取消标记" : "标记").frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.fsTertiaryBg)
                                    .foregroundColor(.fsPrimary)
                                    .cornerRadius(10)
                            }
                            Button(role: .destructive) {
                                fileToDelete = f
                            } label: {
                                Text("删除该文件").frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundColor(.red)
                                    .cornerRadius(10)
                            }
                        }
                        .padding(.top, 20)
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
        .alert("删除文件", isPresented: Binding(
            get: { fileToDelete != nil },
            set: { if !$0 { fileToDelete = nil } }
        )) {
            Button("取消", role: .cancel) { fileToDelete = nil }
            Button("删除", role: .destructive) {
                if let f = fileToDelete {
                    FileRepository.shared.deleteFiles(ids: [f.id])
                    router.pop()
                }
                fileToDelete = nil
            }
        } message: {
            if let f = fileToDelete {
                Text("确定要删除文件「\(f.fileName)」吗？该操作不可撤销。")
            }
        }
    }
}

// MARK: - 文件详情排布（对齐安卓：单行单列 + 一行多列混合）
private func DetailRow(_ label: String, _ value: String, isPath: Bool = false, isMono: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(label).fsFont(.caption).foregroundColor(.fsSecondaryLabel)
        Text(value)
            .fsFont(.subheadline, design: isMono ? .monospaced : .default)
            .fontWeight(.medium)
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(isPath ? 4 : nil)
        Divider().padding(.top, 8)
    }
    .padding(.vertical, 8)
}

private func DetailRowColumns(_ items: [(String, String)]) -> some View {
    VStack(spacing: 0) {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
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
        .padding(.vertical, 8)
        Divider()
    }
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

    init(fileId: Int64, mode: String) {
        self.fileId = fileId
        self.mode = mode
        self._modeState = State(initialValue: mode)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 信息栏 + 字号调节（对齐安卓底部信息栏：字号 / 编码 / 已加载行数）
            HStack(spacing: 12) {
                Button { if fontPt > 10 { fontPt -= 1 } } label: { Image(systemName: "textformat.size.smaller") }
                Text("\(Int(fontPt))")
                    .frame(minWidth: 28).multilineTextAlignment(.center)
                Button { if fontPt < 30 { fontPt += 1 } } label: { Image(systemName: "textformat.size.larger") }
                Divider()
                Text("编码: \(file?.encoding.isEmpty ?? true ? "UTF-8" : (file?.encoding ?? "UTF-8"))")
                    .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                Spacer()
                Text("已加载 \(totalLines) 行").fsFont(.caption).foregroundColor(.fsSecondaryLabel)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.fsSecondaryBg)

            // 文本 + 自定义滑条（横/竖由设置 previewScrollbarMode 控制，对齐安卓）
            ZStack {
                ScrollableText(text: text, fontPt: fontPt,
                               mode: prefs.previewScrollbarMode == "horizontal" ? .horizontal : .vertical,
                               allLines: nil,
                               state: scrollState)
                MiniScrollBar(state: scrollState,
                              axis: prefs.previewScrollbarMode == "horizontal" ? .horizontal : .vertical)
            }
            .edgesIgnoringSafeArea(.bottom)
        }
        .navigationTitle("预览")
        .navigationBarTitleDisplayMode(.inline)
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
        guard let f = FileRepository.shared.getById(fileId) else {
            await MainActor.run { text = "文件不存在" }
            return
        }
        await MainActor.run { file = f }
        let content = await readFileContent(f, mode: modeState)
        await MainActor.run {
            text = content ?? "无法读取文件内容（可能缺少文件夹访问权限，请重新扫描以刷新授权）"
            totalLines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        }
    }

    // 安全作用域访问必须在主线程；读取文件本身放到后台，避免大文件阻塞 UI。
    private func readFileContent(_ f: ScannedFile, mode: String) async -> String? {
        guard let run = FileRepository.shared.getScanRun(f.scanRunId),
              let folderURL = resolveBookmarkURL(run.folderUri) else { return nil }
        let url = URL(fileURLWithPath: f.path)
        // 在主线程开启安全作用域访问
        let accessed = await MainActor.run { folderURL.startAccessingSecurityScopedResource() }
        guard accessed else { return nil }
        // 读取已在后台线程完成，此处切回主线程（瞬间操作）关闭安全作用域，避免异步 defer 与视图生命周期竞态。
        defer { Task { @MainActor in folderURL.stopAccessingSecurityScopedResource() } }

        let enc = f.encoding.isEmpty ? "UTF-8" : f.encoding
        let encoding = EncodingUtil.stringEncoding(named: enc)
        // 预览仅读取前/后 200KB，避免大文件整篇载入导致内存暴涨与界面卡死。
        let maxBytes = 200 * 1024
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }

        var data: Data
        var truncatedSuffix: String
        if mode == "tail" {
            let total = (try? fh.seekToEnd()) ?? 0
            let offset = max(0, Int64(total) - Int64(maxBytes))
            fh.seek(toFileOffset: UInt64(offset))
            data = fh.readData(ofLength: maxBytes)
            let truncated = offset > 0
            truncatedSuffix = truncated ? "\n\n…（预览仅显示末尾 \(maxBytes / 1024) KB，完整内容请在原文件查看）" : ""
        } else if mode == "all" {
            fh.seek(toFileOffset: 0)
            data = fh.readData(ofLength: maxBytes)
            let truncated = data.count >= maxBytes
            truncatedSuffix = truncated ? "\n\n…（预览仅显示前 \(maxBytes / 1024) KB，完整内容请在原文件查看）" : ""
        } else {
            fh.seek(toFileOffset: 0)
            data = fh.readData(ofLength: maxBytes)
            let truncated = data.count >= maxBytes
            truncatedSuffix = truncated ? "\n\n…（预览仅显示前 \(maxBytes / 1024) KB，完整内容请在原文件查看）" : ""
        }
        if let s = String(data: data, encoding: encoding) { return s + truncatedSuffix }
        if let s = String(data: data, encoding: .utf8) { return s + truncatedSuffix }
        return nil
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
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.backgroundColor = .clear
        tv.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(tv)
        NSLayoutConstraint.activate([
            tv.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 12),
            tv.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -12),
            tv.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 12),
            tv.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -12),
            tv.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -24)
        ])
        scroll.delegate = context.coordinator
        context.coordinator.state = state
        context.coordinator.scroll = scroll
        context.coordinator.textView = tv
        state.scrollView = scroll
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        guard let tv = scroll.subviews.first(where: { $0 is UITextView }) as? UITextView else { return }
        // 文本或字号未变化时跳过重设富文本与布局，避免每次 body 重算都同步重建大段 NSAttributedString 阻塞主线程。
        if context.coordinator.lastText != text || context.coordinator.lastFontPt != fontPt {
            context.coordinator.lastText = text
            context.coordinator.lastFontPt = fontPt
            let font = UIFont.systemFont(ofSize: fontPt)
            let attributed = NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: UIColor.label
            ])
            tv.attributedText = attributed
            tv.textContainerInset = .zero
            tv.layoutIfNeeded()
            if mode == .horizontal {
                // 横向：高度固定为视口，宽度随内容展开
                tv.frame.size.height = scroll.bounds.height - 24
                tv.sizeToFit()
                scroll.contentSize = CGSize(width: max(tv.frame.width, scroll.bounds.width),
                                           height: scroll.bounds.height - 24)
            }
        }
        context.coordinator.publish(scroll)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, UIScrollViewDelegate {
        weak var state: PreviewScrollState?
        weak var scroll: UIScrollView?
        weak var textView: UITextView?
        var lastText: String?
        var lastFontPt: CGFloat = 0

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
