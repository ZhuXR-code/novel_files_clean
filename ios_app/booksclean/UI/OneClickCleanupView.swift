import SwiftUI

/// 一键清理重复文件（对齐 Android `OneClickCleanup` 引导式流程）。
/// 流程：选文件夹 → 选文件类型 → 选排除目录 → 扫描解析 → 计算重复 → 清单确认 → 删除。
/// 两种入口：
///   1. 引导式 `init(config:)`：从首页进入，用户需选择文件夹并从零扫描（对应安卓 Home 一键清理）。
///   2. `init(runId:)`：对已有文库执行清理（文库长按菜单入口，扫描已完成，直接进入计算重复阶段）。
struct OneClickCleanupView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var scan: ScanStateManager

    enum Phase { case config, scanning, marking, confirm, deleting, done }

    @State private var phase: Phase = .config
    @State private var config: ScanConfig
    @State private var runId: Int64 = -1
    @State private var folderName: String = ""
    @State private var folderUri: String = ""

    @State private var fileTypes: String = "txt"
    @State private var excludedFolders: String = ""      // 逗号分隔，对齐鸿蒙/PC 排除目录
    @State private var recursive: Bool = true
    @State private var deepScan: Bool = false
    @State private var exactHash: Bool = false

    @State private var marking = false
    @State private var checkedCount: Int = 0
    @State private var totalCount: Int = 0
    @State private var dupGroups: Int = 0
    @State private var showReview = false
    @State private var showError = false
    @State private var errorMsg = ""
    @State private var started = false

    // 引导式入口
    init(config: ScanConfig) {
        _config = State(initialValue: config)
        _fileTypes = State(initialValue: config.fileTypes.isEmpty ? "txt" : config.fileTypes)
        _recursive = State(initialValue: config.recursive)
        _deepScan = State(initialValue: config.scanMode == "deep")
        _exactHash = State(initialValue: config.exactHash)
        _excludedFolders = State(initialValue: config.excludedFolders)
        _phase = State(initialValue: .config)
    }

    // 已有文库入口
    init(runId: Int64) {
        _config = State(initialValue: ScanConfig())
        _runId = State(initialValue: runId)
        _phase = State(initialValue: .marking)
    }

    var body: some View {
        VStack(spacing: 0) {
            stepBar
            Divider()
            switch phase {
            case .config:
                configView
            case .scanning:
                scanningView
            case .marking:
                markingView
            case .confirm:
                confirmView
            case .deleting, .done:
                // 删除交由 DeleteConfirmView / DeleteProgressView 路由承载
                Color.clear
            }
        }
        .navigationTitle("一键清理重复文件")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showReview) {
            OneClickReviewSheet(
                runId: runId,
                onClose: { recompute() },
                onCountChanged: { newChecked, newTotal, newDup in
                    checkedCount = newChecked
                    totalCount = newTotal
                    dupGroups = newDup
                }
            )
        }
        .alert("出错了", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: { Text(errorMsg) }
        .onAppear { if phase == .marking && !started { started = true; runMarking() } }
        // 扫描完成后自动进入"计算重复"阶段
        .onChange(of: scan.finished) { finished in
            guard phase == .scanning, finished else { return }
            if scan.status == "completed" || scan.status == "stopped" {
                runId = scan.runId
                runMarking()
            } else if scan.status == "empty" {
                errorMsg = "所选文件夹中没有匹配的文件类型"; showError = true
            } else {
                errorMsg = scan.errorMsg.isEmpty ? "扫描出错" : scan.errorMsg; showError = true
            }
        }
    }

    // MARK: - 步骤条（对齐安卓顶部阶段指示）
    private var stepBar: some View {
        HStack(spacing: 4) {
            stepItem(1, "选择", done: phase != .config, active: phase == .config)
            stepLine
            stepItem(2, "扫描", done: phase == .scanning || phase == .marking || phase == .confirm, active: phase == .scanning)
            stepLine
            stepItem(3, "去重", done: phase == .marking || phase == .confirm, active: phase == .marking)
            stepLine
            stepItem(4, "确认", done: phase == .confirm, active: phase == .confirm)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(Color.fsSecondaryBg)
    }

    private func stepItem(_ n: Int, _ title: String, done: Bool, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle")
                .foregroundColor(done ? .green : active ? .fsPrimary : .fsSecondaryLabel)
            Text(title).fsFont(.caption).foregroundColor(active || done ? .primary : .fsSecondaryLabel)
        }
    }

    private var stepLine: some View {
        Rectangle().fill(Color.fsSeparator).frame(height: 1).frame(maxWidth: 16)
    }

    // MARK: - 阶段1：选择文件夹/类型/排除目录
    private var configView: some View {
        ScrollView {
            MaxWidthContainer {
                VStack(spacing: 18) {
                FSSection("选择文件夹") {
                    Button {
                        showingFolderPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill").foregroundColor(.fsPrimary)
                            Text(folderName.isEmpty ? "点击选择要清理的文件夹" : folderName)
                                .fsFont(.subheadline).foregroundColor(folderName.isEmpty ? .fsSecondaryLabel : .primary)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.fsSecondaryLabel)
                        }
                    }
                    if !folderName.isEmpty {
                        Text("将扫描该文件夹内的文件（可排除子目录）").fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                    }
                }

                FSSection("文件类型") {
                    TextField("逗号分隔，如 txt,epub", text: $fileTypes)
                        .textFieldStyle(.roundedBorder)
                    Text("仅扫描匹配后缀的文件。").fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                }

                FSSection("排除文件夹") {
                    TextField("逗号分隔，如 备份,已读", text: $excludedFolders)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        showingExcludePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "folder.badge.plus").foregroundColor(.fsPrimary)
                            Text("选择排除文件夹").fsFont(.subheadline).foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.fsSecondaryLabel)
                        }
                    }
                    if !excludedList.isEmpty {
                        ForEach(excludedList, id: \.self) { n in
                            HStack {
                                Text(n).fsFont(.subheadline).lineLimit(1)
                                Spacer()
                                Button {
                                    removeExcluded(n)
                                } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.fsSecondaryLabel) }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                    Text("被排除的子目录将完全跳过扫描。").fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                }

                FSSection("扫描选项") {
                    Toggle("递归扫描子目录", isOn: $recursive)
                    Toggle("深度扫描（识别编码）", isOn: $deepScan)
                    Toggle("精确内容去重（按内容指纹）", isOn: $exactHash)
                }

                PrimaryButton(title: "开始扫描") { startScan() }
                    .disabled(folderName.isEmpty)
                    .padding(.horizontal, 4)
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingFolderPicker) {
            FolderPicker { url in
                showingFolderPicker = false
                folderUri = makeBookmark(url) ?? ""
                folderName = url.lastPathComponent
            }
        }
        .sheet(isPresented: $showingExcludePicker) {
            FolderPicker { url in
                showingExcludePicker = false
                let n = url.lastPathComponent.trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty else { return }
                var parts = excludedList
                if !parts.contains(n) { parts.append(n) }
                excludedFolders = parts.joined(separator: ",")
            }
        }
    }

    @State private var showingFolderPicker = false
    @State private var showingExcludePicker = false

    /// 已配置的排除文件夹（从逗号分隔字符串解析）
    private var excludedList: [String] {
        excludedFolders.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func removeExcluded(_ n: String) {
        var parts = excludedList
        parts.removeAll { $0 == n }
        excludedFolders = parts.joined(separator: ",")
    }

    private func startScan() {
        guard !folderUri.isEmpty else {
            errorMsg = "请先选择文件夹"; showError = true; return
        }
        var cfg = config
        cfg.name = folderName
        cfg.folderUri = folderUri
        cfg.folderName = folderName
        cfg.fileTypes = fileTypes.trimmingCharacters(in: .whitespaces)
        cfg.excludedFolders = excludedFolders.trimmingCharacters(in: .whitespaces)
        cfg.recursive = recursive
        cfg.scanMode = deepScan ? "deep" : "quick"
        cfg.exactHash = exactHash
        config = cfg
        runId = -1
        phase = .scanning
        scan.reset()
        Task { _ = await ScanService.shared.scan(config: cfg) }
    }

    // MARK: - 阶段2：扫描中（内嵌进度，复用 ScanStateManager）
    private var scanningView: some View {
        VStack(spacing: 22) {
            Spacer().frame(height: 20)
            Image(systemName: scan.finished ? "checkmark.circle.fill" : "doc.text.magnifyingglass")
                .fsFontSize(54).foregroundColor(scan.finished ? .green : .fsPrimary)
            Text(scan.phaseText).fsFont(.headline)
            ProgressView(value: Double(scan.progress), total: 100).progressViewStyle(.linear).frame(maxWidth: 280)
            Text("\(scan.scannedFiles) / \(scan.totalFiles)").foregroundColor(.fsSecondaryLabel)
            if !scan.currentFile.isEmpty {
                Text(scan.currentFile).fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                    .lineLimit(1).frame(maxWidth: 280)
            }
            if scan.isScanning {
                Button { scan.requestStop() } label: {
                    Text("停止扫描").foregroundColor(.red).padding(.horizontal, 24).padding(.vertical, 8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red))
                }
            }
            if scan.finished {
                Text(scan.statusText).foregroundColor(.fsSecondaryLabel)
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - 阶段3：计算重复
    private var markingView: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 20)
            if marking {
                ProgressView()
                Text("正在计算重复文件…").fsFont(.headline)
            } else if checkedCount == 0 {
                Image(systemName: "checkmark.circle").fsFontSize(48).foregroundColor(.green)
                Text("未发现重复文件").fsFont(.headline)
                Text("当前规则下没有判定为重复的待删文件。").fsFont(.caption).foregroundColor(.fsSecondaryLabel)
            } else {
                Image(systemName: "exclamationmark.triangle.fill").fsFontSize(48).foregroundColor(.orange)
                Text("发现 \(checkedCount) 个重复文件").fsFont(.headline)
                Text("共 \(dupGroups) 组重复 · 来自 \(totalCount) 个文件")
                    .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - 阶段4：确认删除（含查看清单）
    private var confirmView: some View {
        ScrollView {
            MaxWidthContainer {
                VStack(spacing: 18) {
                FSSection("待删除清单") {
                    VStack(alignment: .leading, spacing: 8) {
                        statRow("重复文件数", "\(checkedCount)")
                        statRow("重复组数", "\(dupGroups)")
                        statRow("涉及文件总数", "\(totalCount)")
                    }
                }
                FSSection("操作") {
                    Button {
                        showReview = true
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet").foregroundColor(.fsPrimary)
                            Text("查看待删除清单")
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.fsSecondaryLabel)
                        }
                    }
                }
                PrimaryButton(title: "确认删除") { confirmDelete() }
                    .disabled(checkedCount == 0)
                    .padding(.horizontal, 4)
                Text("删除前请务必在清单中核对，操作不可恢复。").fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding()
            }
        }
    }

    private func statRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).fsFont(.subheadline).foregroundColor(.fsSecondaryLabel)
            Spacer()
            Text(v).fsFont(.subheadline).fontWeight(.medium)
        }
    }

    // MARK: - 逻辑
    private func runMarking() {
        marking = true
        phase = .marking
        DispatchQueue.global(qos: .userInitiated).async {
            let ids = FileRepository.shared.selectDuplicateIds(runId: runId)
            let dup = FileRepository.shared.getDuplicateGroups(runId: runId)
            let total = FileRepository.shared.countFiles(runId: runId)
            DispatchQueue.main.async {
                marking = false
                checkedCount = ids.count
                dupGroups = dup
                totalCount = total
                if ids.isEmpty {
                    phase = .marking // 停留在提示界面
                } else {
                    phase = .confirm
                }
            }
        }
    }

    private func recompute() {
        runMarking()
    }

    private func confirmDelete() {
        guard checkedCount > 0 else { return }
        let ids = FileRepository.shared.getCheckedIds(runId: runId)
        phase = .deleting
        // 默认 physical=false（仅删除记录），更安全；用户在 DeleteConfirmView 内可主动开启 Toggle 切换为同步删除磁盘文件
        router.navigate(.deleteConfirm(runId: runId, ids: Array(ids), physical: false))
    }
}

// MARK: - 待删除清单弹框（对齐安卓 confirm 页"查看清单"）
struct OneClickReviewSheet: View {
    let runId: Int64
    var onClose: (() -> Void)? = nil
    /// 移除单条后回调（剩余勾选数, 剩余涉及文件总数, 剩余重复组数），用于父级同步顶部统计。
    var onCountChanged: ((Int, Int, Int) -> Void)? = nil
    @Environment(\.dismiss) var dismiss

    @State private var files: [ScannedFile] = []
    @State private var loading = true
    @State private var searchText = ""

    /// 模糊搜索过滤后的清单（匹配 文件名/书名/作者）
    private var filteredFiles: [ScannedFile] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return files }
        return files.filter {
            $0.fileName.lowercased().contains(q)
                || $0.title.lowercased().contains(q)
                || $0.author.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                } else if files.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle").fsFontSize(40).foregroundColor(.green)
                        Text("清单已清空，无需删除。").foregroundColor(.fsSecondaryLabel)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        TextField("搜索文件名 / 书名 / 作者", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 12).padding(.top, 8)
                        HStack(spacing: 6) {
                            Image(systemName: "hand.point.up.left.fill").foregroundColor(.fsPrimary)
                            Text("不需要删除的文件：点击行右侧红色").fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                            Text("移除").fsFont(.caption2).foregroundColor(.red).fontWeight(.semibold)
                            Text("按钮，或左滑该行。").fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 6)

                        if filteredFiles.isEmpty {
                            Text("未找到匹配的文件").fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                                .frame(maxWidth: .infinity).padding(.vertical, 24)
                        } else {
                            List {
                                ForEach(filteredFiles) { f in
                                    OneClickReviewRow(file: f) {
                                        removeFromList(f)
                                    }
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) { removeFromList(f) } label: {
                                            Label("移除", systemImage: "xmark.circle")
                                        }
                                    }
                                }
                            }
                            .listStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("待删除清单（\(files.count)）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        onClose?()
                        dismiss()
                    }
                }
            }
            .task { load() }
        }
    }

    /// 将文件从本次待删除清单中移除（数据库 checked=0，下次 confirmDelete 不会取到）。
    private func removeFromList(_ f: ScannedFile) {
        // 1) 数据库：取消勾选
        FileRepository.shared.setChecked(id: f.id, checked: false)
        // 2) 本地数组移除
        files.removeAll { $0.id == f.id }
        // 3) 重新拉统计，通知父级同步顶部数字
        let newChecked = FileRepository.shared.getCheckedIds(runId: runId).count
        let newTotal = FileRepository.shared.countFiles(runId: runId)
        let newDup = FileRepository.shared.getDuplicateGroups(runId: runId)
        onCountChanged?(newChecked, newTotal, newDup)
    }

    private func load() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let rows = FileRepository.shared.getCheckedFiles(runId: runId)
            DispatchQueue.main.async {
                files = rows
                loading = false
            }
        }
    }
}

/// 一键清理查看清单的单行：文件名 + 书名/作者 + 大小 + 红色"移除"按钮。
private struct OneClickReviewRow: View {
    let file: ScannedFile
    /// 从清单中移除该文件（本次不删除）
    var onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(file.fileName).fsFont(.subheadline).fontWeight(.medium)
                    .foregroundColor(.fsPrimary).lineLimit(1)
                HStack {
                    Text(file.title.isEmpty ? "未解析" : file.title)
                        .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                        .lineLimit(1)
                    if !file.author.isEmpty {
                        Text("· \(file.author)").fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(FormatUtil.formatSize(file.fileSize)).fsFont(.caption)
                        .foregroundColor(.fsSecondaryLabel)
                }
            }
            Spacer(minLength: 0)
            Button(action: onRemove) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill").fsFontSize(20)
                    Text("移除").fsFont(.caption2)
                }
                .foregroundColor(.red)
                .padding(.vertical, 4).padding(.leading, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("从清单移除")
            .help("从清单移除")
        }
    }
}
