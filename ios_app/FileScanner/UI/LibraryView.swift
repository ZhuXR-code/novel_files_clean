import SwiftUI

private let LIBRARY_PAGE_SIZE = 50
private let SORT_OPTIONS: [(String, String)] = [
    ("created_at", "扫描顺序"), ("file_size", "文件大小"), ("file_name", "文件名"),
    ("title", "书名"), ("author", "作者"), ("progress", "进度"), ("source", "来源")
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
            Spacer(minLength: 4)
            Button { onToggleMark() } label: {
                Image(systemName: file.marked == 1 ? "star.fill" : "star")
                    .foregroundColor(file.marked == 1 ? .yellow : .fsSecondaryLabel)
            }
        }
        .contentShape(Rectangle()).onTapGesture { onTap() }
    }
}

// 步骤指示器（对齐安卓文库页顶部的「扫描→合集→勾选重复→确认→删除」步骤条）
private let LIB_STEPS = ["扫描", "合集", "勾选重复", "确认", "删除"]
struct LibraryStepBar: View {
    let current: Int
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LIB_STEPS.indices, id: \.self) { i in
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
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var prefs: Preferences
    let runId: Int64

    @State private var mode = "list"
    @State private var files: [ScannedFile] = []
    @State private var groups: [NovelGroup] = []
    @State private var total = 0
    @State private var page = 0
    @State private var pageCount = 1
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
    @State private var currentStep = 0            // 步骤指示器当前步
    @State private var autoCollapse = false
    @State private var showGroupSettings = false
    @State private var showDeleteConfirm = false
    @State private var toastText: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // 步骤指示器（对齐安卓文库顶部步骤条）
            LibraryStepBar(current: currentStep).padding(.vertical, 6)

            Picker("模式", selection: $mode) {
                Text("列表").tag("list")
                Text("合集").tag("group")
            }
            .pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 6)

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
        .onChange(of: mode) { _ in reload() }
        .onChange(of: sortBy) { _ in reload() }
        .onChange(of: ascending) { _ in reload() }
        .onChange(of: search) { v in if v.isEmpty { reload() } }
        .onChange(of: selectedFilter) { _ in reload() }
        .onAppear { reload() }
        .sheet(isPresented: $showFilter) { filterSheet }
        .sheet(isPresented: $showGroupSettings) { groupSettingsSheet }
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
                currentStep = max(currentStep, 4)
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

    // MARK: 列表模式
    private var listContent: some View {
        List {
            ForEach(files) { f in
                FileRow(
                    file: f,
                    onToggleCheck: { toggleCheck(f) },
                    onToggleMark: { toggleMark(f) },
                    onTap: { router.navigate(.fileDetail(id: f.id)) }
                )
                .swipeActions(edge: .leading) {
                    Button { router.navigate(.filePreview(id: f.id, all: false)) } label: { Label("预览", systemImage: "eye") }
                }
            }
            if total > LIBRARY_PAGE_SIZE {
                HStack {
                    Button { if page > 0 { page -= 1; reload() } } label: { Image(systemName: "chevron.left") }.disabled(page <= 0)
                    Spacer()
                    Text("第 \(page + 1) / \(pageCount) 页").fsFont(.caption)
                    Spacer()
                    Button { if page < pageCount - 1 { page += 1; reload() } } label: { Image(systemName: "chevron.right") }.disabled(page >= pageCount - 1)
                }.padding(.vertical, 6)
            }
        }
        .listStyle(.plain)
    }

    // MARK: 合集模式
    private var groupContent: some View {
        List {
            ForEach(groups) { g in
                HStack {
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

    private var toolbarItems: some ToolbarContent {
        Group {
            // 常驻操作（对齐安卓文库顶部图标栏：勾选重复 / 删除选中 / 更多）
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    FileRepository.shared.selectDuplicateIds(runId: runId)
                    reload()
                    currentStep = max(currentStep, 2)
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

    private func reload() {
        let repo = FileRepository.shared
        if mode == "group" {
            groups = repo.dbGroupFiles(runId: runId, min: prefs.groupMinCount, max: prefs.groupMaxCount,
                                       exclude: LibraryLogic.parseExcludeNames(prefs.groupExcludeNames))
            return
        }
        // 筛选 chips 映射（对齐安卓文库全部/已勾选/未勾选/已标记/未标记）
        let (cf, mf): (Int, Int) = {
            switch selectedFilter {
            case "checked":   return (1, -1)
            case "unchecked": return (0, -1)
            case "marked":    return (-1, 1)
            case "unmarked":  return (-1, 0)
            default:          return (-1, -1)
            }
        }()
        total = repo.dbCountFiles(runId: runId, title: titleFilter, author: authorFilter,
                                  progress: progressFilter, source: sourceFilter, search: search,
                                  checkedFilter: cf, markedFilter: mf)
        pageCount = LibraryLogic.computePageCount(total: max(total, 1), pageSize: LIBRARY_PAGE_SIZE)
        if page >= pageCount { page = pageCount - 1 }
        if page < 0 { page = 0 }
        files = repo.dbPageFiles(runId: runId, page: page, pageSize: LIBRARY_PAGE_SIZE, sortBy: sortBy,
                                 ascending: ascending, title: titleFilter, author: authorFilter,
                                 progress: progressFilter, source: sourceFilter, search: search,
                                 checkedFilter: cf, markedFilter: mf)
        selectAllOnPage = false
    }
}

extension FileRepository {
    func dbPageFiles(runId: Int64, page: Int, pageSize: Int, sortBy: String, ascending: Bool,
                     title: String, author: String, progress: String, source: String, search: String,
                     checkedFilter: Int = -1, markedFilter: Int = -1) -> [ScannedFile] {
        DatabaseManager.shared.getScannedFilesPaged(runId: runId, offset: page * pageSize, limit: pageSize,
                                                     sortBy: sortBy, ascending: ascending, titleFilter: title,
                                                     authorFilter: author, progressFilter: progress,
                                                     sourceFilter: source, search: search,
                                                     checkedFilter: checkedFilter, markedFilter: markedFilter)
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
        .onAppear { files = DatabaseManager.shared.getGroupFiles(runId: runId, title: title, author: author) }
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
    @State private var showRename = false
    @State private var newName = ""

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
                        DetailRow("路径", f.path.isEmpty ? "—" : f.path, isPath: true)

                        // 操作按钮（对齐安卓：预览 / 重命名 / 删除）
                        VStack(spacing: 12) {
                            PrimaryButton(title: "预览内容") {
                                router.navigate(.filePreview(id: f.id, all: false))
                            }
                            Button {
                                newName = f.fileName; showRename = true
                            } label: {
                                Text("重命名").frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.fsTertiaryBg)
                                    .foregroundColor(.fsPrimary)
                                    .cornerRadius(10)
                            }
                            Button {
                                FileRepository.shared.setMarked(id: f.id, marked: f.marked == 1)
                                file = FileRepository.shared.getById(f.id)
                            } label: {
                                Text(f.marked == 1 ? "取消标记" : "标记为已读").frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.fsTertiaryBg)
                                    .foregroundColor(.fsPrimary)
                                    .cornerRadius(10)
                            }
                            Button(role: .destructive) {
                                FileRepository.shared.deleteFiles(ids: [f.id])
                                router.pop()
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
        .onAppear { file = FileRepository.shared.getById(fileId) }
        .sheet(isPresented: $showRename) {
            NavigationStack {
                Form { TextField("新文件名", text: $newName) }
                .navigationTitle("重命名").navigationBarTitleDisplayMode(.inline).toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { Button("取消") { showRename = false } }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("保存") {
                            FileRepository.shared.updateFileName(id: fileId, newName: newName)
                            file = FileRepository.shared.getById(fileId)
                            showRename = false
                        }
                    }
                }
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

// MARK: - 文件预览（阅读，对齐安卓）
struct FilePreviewView: View {
    let fileId: Int64
    let all: Bool
    @EnvironmentObject var prefs: Preferences
    @State private var text = "加载中…"
    @State private var totalLines = 0
    @State private var showAll = false
    @State private var fontPt: CGFloat = 16
    @StateObject private var scrollState = PreviewScrollState()
    @State private var file: ScannedFile?

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
                               state: scrollState,
                               onLineCount: { totalLines = $0 })
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
                    Button(showAll ? "仅显示解析行" : "显示全部内容") { showAll.toggle(); Task { await load() } }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let f = FileRepository.shared.getById(fileId) else { text = "文件不存在"; return }
        file = f
        let content = readFileContent(f)
        await MainActor.run { text = content ?? "无法读取文件内容（可能缺少文件夹访问权限，请重新扫描以刷新授权）" }
    }

    private func readFileContent(_ f: ScannedFile) -> String? {
        guard let run = FileRepository.shared.getScanRun(f.scanRunId),
              let url = URL(string: f.path),
              let folderURL = resolveBookmarkURL(run.folderUri) else { return nil }
        guard folderURL.startAccessingSecurityScopedResource() else { return nil }
        defer { folderURL.stopAccessingSecurityScopedResource() }
        let enc = f.encoding.isEmpty ? "UTF-8" : f.encoding
        let encoding = EncodingUtil.stringEncoding(named: enc)
        // 仅读取前 200KB 预览，避免大文件（数十 MB）整篇载入导致内存暴涨与界面卡死。
        let maxBytes = 200 * 1024
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        let data = fh.readData(ofLength: maxBytes)
        let truncated = data.count >= maxBytes
        let tail = truncated ? "\n\n…（预览仅显示前 \(maxBytes / 1024) KB，完整内容请在原文件查看）" : ""
        if let s = String(data: data, encoding: encoding) { return s + tail }
        if let s = String(data: data, encoding: .utf8) { return s + tail }
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
    let onLineCount: (Int) -> Void

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
        onLineCount(text.split(separator: "\n", omittingEmptySubsequences: false).count)
        context.coordinator.publish(scroll)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, UIScrollViewDelegate {
        weak var state: PreviewScrollState?
        weak var scroll: UIScrollView?
        weak var textView: UITextView?

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
