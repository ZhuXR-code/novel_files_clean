import SwiftUI

struct DeleteConfirmView: View {
    @EnvironmentObject var router: Router
    let runId: Int64
    let ids: [Int64]
    @State private var physical: Bool
    /// 待删除文件完整对象（供清单展示）
    @State private var files: [ScannedFile] = []
    /// 选中集：默认全选，可逐条取消（对齐安卓/鸿蒙删除确认页）
    @State private var selectedIDs: Set<Int64> = []
    /// 选中文件合计大小缓存：在 toggle/全选/移除时增量维护，
    /// 避免把 selectedFiles/totalSize 写成 computed property —— 那会导致每次 body 求值
    /// 都对全部文件（可能上万）做 O(n) filter + reduce，滚动/搜索/toggle 时明显卡顿。
    @State private var totalSizeCache: Int64 = 0
    /// 清单加载完成标记
    @State private var loading = true
    /// 清单模糊搜索关键字
    @State private var searchText = ""

    init(runId: Int64, ids: [Int64], physical: Bool = true) {
        self.runId = runId
        self.ids = ids
        _physical = State(initialValue: physical)
        _selectedIDs = State(initialValue: Set(ids))
    }

    /// 当前勾选的文件 id（仅「开始删除」时取一次，避免在 body 中重复全量过滤）
    private var selectedFileIDs: [Int64] {
        files.filter { selectedIDs.contains($0.id) }.map { $0.id }
    }

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

    /// 将文件从本次待删除清单中移除（不删除磁盘文件与扫描记录）
    private func removeFromList(_ f: ScannedFile) {
        files.removeAll { $0.id == f.id }
        if selectedIDs.remove(f.id) != nil {
            totalSizeCache -= f.fileSize
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部红色警告条（对齐安卓删除确认页 warning）
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.white)
                Text("删除操作不可恢复，请确认勾选的文件无误。").fsFont(.subheadline).foregroundColor(.white)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12).padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(Color.red)

            VStack(spacing: 12) {
                Spacer().frame(height: 12)
                Image(systemName: "trash").fsFontSize(40).foregroundColor(.red)
                Text("确认删除").fsFont(.title3).fontWeight(.semibold)
                // 已选 / 共 统计（对齐安卓底部统计条）
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text("已选 \(selectedIDs.count) / 共 \(files.count)").fsFont(.headline).foregroundColor(.fsPrimary)
                        Text("待删除文件").fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                    }
                    Divider().frame(height: 28)
                    VStack(spacing: 2) {
                        Text(FormatUtil.formatSize(totalSizeCache)).fsFont(.headline).foregroundColor(.fsPrimary)
                        Text("合计大小").fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $physical) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(physical ? "同时删除磁盘上的文件" : "仅删除记录（不删磁盘文件）")
                                .fsFont(.subheadline).fontWeight(.medium)
                            Text(physical ? "将尝试从磁盘永久删除源文件，操作不可恢复" : "仅移除数据库记录，源文件保留在原位置")
                                .fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                        }
                    }
                    .tint(.red)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.fsSecondaryBg)
                .cornerRadius(10)

                // 待删除文件清单（可滚动浏览，默认全选，可逐条取消；支持模糊搜索 + 移出清单）
                if loading {
                    ProgressView("加载清单…").frame(maxWidth: .infinity)
                } else if files.isEmpty {
                    Text("清单已清空，无需删除。").fsFont(.subheadline).foregroundColor(.fsSecondaryLabel)
                        .frame(maxWidth: .infinity).padding(.vertical, 32)
                } else {
                    HStack {
                        Text("待删除清单").fsFont(.subheadline).fontWeight(.medium).foregroundColor(.fsPrimary)
                        Spacer()
                        // 一键全选 / 取消全选（同步维护合计大小缓存）
                        Button(selectedIDs.count == files.count ? "取消全选" : "全选") {
                            if selectedIDs.count == files.count {
                                selectedIDs = []
                                totalSizeCache = 0
                            } else {
                                selectedIDs = Set(files.map(\.id))
                                totalSizeCache = files.reduce(0) { $0 + $1.fileSize }
                            }
                        }
                        .fsFont(.caption)
                        .foregroundColor(.fsPrimary)
                    }
                    .padding(.horizontal, 4)

                    TextField("搜索文件名 / 书名 / 作者", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    HStack(spacing: 6) {
                        Image(systemName: "hand.point.up.left.fill")
                            .foregroundColor(.fsPrimary)
                        Text("不需要删除的文件：点击行右侧红色").fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                        Text("移除").fsFont(.caption2).foregroundColor(.red).fontWeight(.semibold)
                        Text("按钮，或左滑该行。").fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if filteredFiles.isEmpty {
                        Text("未找到匹配的文件").fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                            .frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else {
                        List {
                            ForEach(filteredFiles) { f in
                                DeleteConfirmRow(file: f, isOn: Binding(
                                    get: { selectedIDs.contains(f.id) },
                                    set: { on in
                                        if on {
                                            selectedIDs.insert(f.id)
                                            totalSizeCache += f.fileSize
                                        } else {
                                            selectedIDs.remove(f.id)
                                            totalSizeCache -= f.fileSize
                                        }
                                    }
                                )) {
                                    removeFromList(f)
                                }
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) { removeFromList(f) } label: {
                                        Label("移出清单", systemImage: "xmark.circle")
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }

                PrimaryButton(title: "开始删除（\(selectedIDs.count)）", enabled: !selectedIDs.isEmpty && !files.isEmpty) {
                    let finalIDs = files.filter { selectedIDs.contains($0.id) }.map { $0.id }
                    router.navigate(.deleteProgress(runId: runId, ids: finalIDs, physical: physical))
                }
                Spacer()
            }
            .padding(.horizontal)
        }
        .navigationTitle("删除确认")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadFiles() }
    }

    private func loadFiles() async {
        let loaded = FileRepository.shared.getByIds(ids)
        await MainActor.run {
            files = loaded
            selectedIDs = Set(loaded.map(\.id))
            totalSizeCache = loaded.reduce(0) { $0 + $1.fileSize }
            loading = false
        }
    }
}

/// 删除确认页的单个文件行：勾选框 + 书名/文件名 + 大小 + 路径
private struct DeleteConfirmRow: View {
    let file: ScannedFile
    @Binding var isOn: Bool
    /// 从清单中移除该文件（本次不删除）
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.red)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.title.isEmpty ? file.fileName : file.title)
                    .fsFont(.subheadline).fontWeight(.medium)
                    .foregroundColor(.fsPrimary)
                    .lineLimit(1)
                Text(file.fileName)
                    .fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                    .lineLimit(1)
                Text("\(FormatUtil.formatSize(file.fileSize)) · \(FormatUtil.toHumanReadablePath(file.path))")
                    .fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let onRemove = onRemove {
                Button(action: onRemove) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .fsFontSize(22)
                        Text("移除").fsFont(.caption2)
                    }
                    .foregroundColor(.red)
                    .padding(.vertical, 6)
                    .padding(.leading, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("从删除清单移除")
                .help("从清单移除")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // 点击整行也可切换勾选（对齐安卓逐条点击取消）
            isOn.toggle()
        }
    }
}

struct DeleteProgressView: View {
    @EnvironmentObject var router: Router
    let runId: Int64
    let ids: [Int64]
    let physical: Bool

    @State private var progress = 0
    @State private var deletedCount = 0
    @State private var failedCount = 0
    @State private var finished = false
    @State private var errorMsg = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 20)
            Image(systemName: finished ? "checkmark.circle.fill" : "trash")
                .fsFontSize(48).foregroundColor(finished ? .green : .red)
            Text(finished ? "删除完成" : "正在删除…").fsFont(.headline)
            ProgressView(value: Double(progress), total: 100).frame(maxWidth: 280)
            Text("成功 \(deletedCount) · 失败 \(failedCount) / 共 \(ids.count)")
                .foregroundColor(.fsSecondaryLabel)
            if finished {
                if !errorMsg.isEmpty {
                    Text(errorMsg).fsFont(.caption).foregroundColor(.red).frame(maxWidth: 280)
                }
                PrimaryButton(title: "返回文库") {
                    router.path = [.library(runId: runId)]
                }.frame(maxWidth: 240)
            }
            Spacer()
        }
        .padding().navigationTitle("删除中").navigationBarBackButtonHidden(true)
        .task { await runDelete() }
    }

    private func runDelete() async {
        guard let run = FileRepository.shared.getScanRun(runId) else {
            await MainActor.run { finished = true; errorMsg = "未找到文库信息" }; return
        }
        let files = FileRepository.shared.getByIds(ids)
        var folderURL: URL?
        if physical {
            folderURL = resolveBookmarkURL(run.folderUri)?.url
        }
        let accessing = folderURL?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { folderURL?.stopAccessingSecurityScopedResource() } }

        var deleted = 0, failed = 0
        // 进度回调节流：与扫描侧节流对齐（每 64 个文件跳一次主线程）。
        // 10w 文件若每删一个就 await MainActor.run 更新 3 个 @State，
        // 主线程需承受 10w 次跳转 + SwiftUI 重渲染，进度页会明显卡顿。
        let interval = 64
        var lastReported = 0
        for (i, f) in files.enumerated() {
            if physical, let u = URL(string: f.path) {
                do { try FileManager.default.removeItem(at: u); deleted += 1 }
                catch { failed += 1; LogUtil.e("Delete", "删除失败 \(f.fileName): \(error)"); FileRepository.shared.logOperation(level: "W", tag: "删除", message: "删除文件失败：\(f.fileName)（\(error.localizedDescription)）") }
            }
            let done = i + 1
            if done - lastReported >= interval {
                lastReported = done
                let p = Int(done * 100 / max(files.count, 1))
                await MainActor.run { progress = p; deletedCount = deleted; failedCount = failed }
            }
        }
        FileRepository.shared.deleteFiles(ids: ids)
        FileRepository.shared.logOperation(level: "I", tag: "删除", message: "删除 \(deleted) 个文件（失败 \(failed)），physical=\(physical)")
        // 强制补报最终状态：小批量（< interval）时循环内可能一次都没触发，
        // 直接在完成态一次性写入 100% 与成败计数。
        await MainActor.run {
            progress = 100
            deletedCount = deleted
            failedCount = failed
            finished = true
            if failed > 0 { errorMsg = "\(failed) 个文件因权限或已被移动而删除失败（数据库记录已移除）" }
        }
    }
}
