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
                    .font(.title3).foregroundColor(file.checked == 1 ? .fsPrimary : .fsSecondaryLabel)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(file.fileName).font(.subheadline).fontWeight(.medium).lineLimit(1)
                if !file.title.isEmpty {
                    Text("《\(file.title)》").font(.caption).foregroundColor(.fsSecondaryLabel).lineLimit(1)
                }
                HStack(spacing: 8) {
                    if !file.author.isEmpty { Text("作者: \(file.author)").font(.caption).foregroundColor(.fsSecondaryLabel) }
                    if !file.progress.isEmpty { Text("进度: \(file.progress)").font(.caption).foregroundColor(.fsSecondaryLabel) }
                    if !file.source.isEmpty { Text("来源: \(file.source)").font(.caption).foregroundColor(.fsSecondaryLabel) }
                }
                Text(FormatUtil.formatSize(file.fileSize) + " · " + FormatUtil.formatFileDate(file.fileDate))
                    .font(.caption2).foregroundColor(.fsSecondaryLabel)
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

    var body: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $mode) {
                Text("列表").tag("list")
                Text("合集").tag("group")
            }
            .pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 6)

            if mode == "list" { listContent } else { groupContent }
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
        .onAppear { reload() }
        .sheet(isPresented: $showFilter) { filterSheet }
        .sheet(item: $selectedGroup) { g in
            NavigationStack {
                GroupFilesView(runId: runId, title: g.title == "(无书名)" ? "" : g.title, author: g.author)
                    .navigationTitle("\(g.title) / \(g.author)")
                    .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { selectedGroup = nil } } }
            }
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
                    Text("第 \(page + 1) / \(pageCount) 页").font(.caption)
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
                        Text(g.title).font(.subheadline).fontWeight(.medium)
                        Text("作者: \(g.author) · \(g.fileCount) 本 · \(FormatUtil.formatSize(g.totalSize))")
                            .font(.caption).foregroundColor(.fsSecondaryLabel)
                    }
                    Spacer()
                    if g.checkedCount > 0 {
                        Text("勾选 \(g.checkedCount)").font(.caption).foregroundColor(.red)
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
            }
            .navigationTitle("筛选").toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("应用") { showFilter = false; page = 0; reload() }
                }
            }
        }
    }

    // MARK: - 操作
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
        total = repo.dbCountFiles(runId: runId, title: titleFilter, author: authorFilter,
                                  progress: progressFilter, source: sourceFilter, search: search)
        pageCount = LibraryLogic.computePageCount(total: max(total, 1), pageSize: LIBRARY_PAGE_SIZE)
        if page >= pageCount { page = pageCount - 1 }
        if page < 0 { page = 0 }
        files = repo.dbPageFiles(runId: runId, page: page, pageSize: LIBRARY_PAGE_SIZE, sortBy: sortBy,
                                 ascending: ascending, title: titleFilter, author: authorFilter,
                                 progress: progressFilter, source: sourceFilter, search: search)
        selectAllOnPage = false
    }
}

extension FileRepository {
    func dbPageFiles(runId: Int64, page: Int, pageSize: Int, sortBy: String, ascending: Bool,
                     title: String, author: String, progress: String, source: String, search: String) -> [ScannedFile] {
        DatabaseManager.shared.getScannedFilesPaged(runId: runId, offset: page * pageSize, limit: pageSize,
                                                     sortBy: sortBy, ascending: ascending, titleFilter: title,
                                                     authorFilter: author, progressFilter: progress,
                                                     sourceFilter: source, search: search)
    }
    func dbCountFiles(runId: Int64, title: String, author: String, progress: String, source: String, search: String) -> Int {
        DatabaseManager.shared.countScannedFiles(runId: runId, titleFilter: title, authorFilter: author,
                                                 progressFilter: progress, sourceFilter: source, search: search)
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
                List {
                    Section("文件信息") {
                        row("文件名", f.fileName)
                        row("路径", f.path)
                        row("大小", FormatUtil.formatSize(f.fileSize))
                        row("书名", f.title.isEmpty ? "—" : "《\(f.title)》")
                        row("作者", f.author.isEmpty ? "—" : f.author)
                        row("进度", f.progress.isEmpty ? "—" : f.progress)
                        row("来源", f.source.isEmpty ? "—" : f.source)
                        row("编码", f.encoding.isEmpty ? "—" : f.encoding)
                        row("修改日期", FormatUtil.formatFileDate(f.fileDate))
                    }
                    Section {
                        Button { router.navigate(.filePreview(id: f.id, all: false)) } label: { Label("预览内容", systemImage: "eye") }
                        Button { newName = f.fileName; showRename = true } label: { Label("重命名", systemImage: "pencil") }
                        Button(f.marked == 1 ? "取消标记" : "标记为已读") {
                            FileRepository.shared.setMarked(id: f.id, marked: f.marked == 1 ? 0 : 1)
                            file = FileRepository.shared.getById(f.id)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("文件详情")
        .onAppear { file = FileRepository.shared.getById(fileId) }
        .sheet(isPresented: $showRename) {
            NavigationStack {
                Form { TextField("新文件名", text: $newName) }
                .navigationTitle("重命名").toolbar {
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

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).foregroundColor(.fsSecondaryLabel).frame(width: 70, alignment: .leading)
            Text(v).textSelection(.enabled)
            Spacer()
        }
    }
}

// MARK: - 文件预览（阅读）
struct FilePreviewView: View {
    let fileId: Int64
    let all: Bool
    @State private var text = "加载中…"

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 16 * Preferences.shared.fontScaleFactor))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("预览")
        .task { await load() }
    }

    private func load() async {
        guard let f = FileRepository.shared.getById(fileId) else { text = "文件不存在"; return }
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
