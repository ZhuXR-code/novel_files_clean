import SwiftUI

struct HomeView: View {
    @EnvironmentObject var router: Router
    @State private var runs: [ScanRun] = []
    @State private var markedFiles: Int = 0
    @State private var showingFolderPicker = false
    @State private var runToDelete: ScanRun? = nil
    @State private var selecting: Bool = false
    @State private var selectedRunIds: Set<Int64> = []
    @State private var showMergeAlert: Bool = false
    @State private var mergeNameInput: String = "合并文库"

    // 统计汇总（对齐安卓：总文件数 / 标记文件数）。totalFiles 由内存中的 runs 计算，
    // markedFiles 在主线程外一次性聚合（避免每个文库各查一次 DB 卡住首屏）。
    private var totalFiles: Int { runs.reduce(0) { $0 + $1.fileCount } }

    var body: some View {
        ScrollView {
            MaxWidthContainer {
                VStack(spacing: 16) {
                    // 统计卡片（对齐安卓顶部统计）
                    HStack(spacing: 12) {
                        statCard(title: "文库数", value: "\(runs.count)", icon: "books.vertical.fill")
                        statCard(title: "总文件数", value: "\(totalFiles)", icon: "doc.fill")
                        statCard(title: "标记文件", value: "\(markedFiles)", icon: "checkmark.seal.fill")
                    }
                    .padding(.top, 4)

                // 一键清理（对齐安卓：引导式流程，从零选择文件夹/类型/排除目录）
                PrimaryButton(title: "一键清理重复文件") {
                    router.navigate(.oneClick(config: ScanConfig()))
                }
                .padding(.horizontal, 2)

                FSSection("快速开始") {
                    VStack(spacing: 10) {
                        PrimaryButton(title: "选择文件夹开始扫描") { showingFolderPicker = true }
                        Button { router.navigate(.configList) } label: {
                            Text("扫描配置").frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(Color.fsTertiaryBg).cornerRadius(10)
                        }
                    }
                }

                // 方法说明（对齐安卓两种扫描方式）
                FSSection("两种扫描方式") {
                    VStack(alignment: .leading, spacing: 12) {
                        methodRow(number: "1", title: "选择文件夹扫描",
                                  desc: "直接选择本地文件夹，解析文件名并标记重复、广告、水印等文件。")
                        Divider()
                        methodRow(number: "2", title: "从文库清理",
                                  desc: "选择已有的扫描文库，对其中的文件进行去重与清理。")
                    }
                    .padding(.vertical, 4)
                }

                FSSection("扫描文库") {
                    HStack {
                        Text("文库列表")
                            .fsFont(.headline)
                        Spacer()
                        if selecting && selectedRunIds.count >= 2 {
                            Button {
                                mergeNameInput = "合并文库"
                                showMergeAlert = true
                            } label: {
                                Label("合并", systemImage: "rectangle.on.rectangle").foregroundColor(.fsPrimary)
                            }
                        }
                    }
                    .padding(.bottom, 4)

                    if runs.isEmpty {
                        Text("暂无扫描记录，点击上方按钮选择文件夹开始。")
                            .foregroundColor(.fsSecondaryLabel).padding(.vertical, 8)
                    } else {
                        ForEach(runs) { run in
                            HStack(spacing: 10) {
                                if selecting {
                                    Image(systemName: selectedRunIds.contains(run.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedRunIds.contains(run.id) ? .fsPrimary : .fsSecondaryLabel)
                                        .fsFont(.title3)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(run.folderName.isEmpty ? run.name : run.folderName)
                                        .fsFont(.subheadline).fontWeight(.medium)
                                    Text("\(run.fileCount) 个文件 · \(formatRunDate(run.createdAt))")
                                        .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                                }
                                Spacer()
                                if !selecting {
                                    Image(systemName: "chevron.right").foregroundColor(.fsSecondaryLabel)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selecting {
                                    if selectedRunIds.contains(run.id) {
                                        selectedRunIds.remove(run.id)
                                    } else {
                                        selectedRunIds.insert(run.id)
                                    }
                                } else {
                                    router.navigate(.library(runId: run.id))
                                }
                            }
                            .contextMenu {
                                // 注意：swipeActions 只在 List 中生效，这里是 ScrollView，故用长按菜单
                                Button(role: .destructive) {
                                    runToDelete = run
                                } label: { Label("删除文库", systemImage: "trash") }

                                Button {
                                    router.navigate(.oneClickExisting(runId: run.id))
                                } label: { Label("一键清理", systemImage: "wand.and.stars") }
                            }
                        }
                    }
                }

                // 隐私提示（对齐安卓本地扫描不上传说明）
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill").foregroundColor(.fsPrimary)
                    Text("所有扫描均在本地完成，文件不会上传。")
                        .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                }
            }
            .padding()
        }
        .navigationTitle(selecting ? "选择文库" : "文包整理清理助手")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if selecting {
                    Button("取消") { selecting = false; selectedRunIds.removeAll() }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    if !selecting {
                        Button {
                            selecting = true
                            selectedRunIds.removeAll()
                        } label: {
                            Text("选择").foregroundColor(.fsPrimary)
                        }
                    }
                    Button { router.navigate(.help) } label: {
                        Image(systemName: "questionmark.circle").foregroundColor(.fsPrimary)
                    }
                    Button { router.navigate(.settings) } label: {
                        Image(systemName: "gearshape.fill").foregroundColor(.fsPrimary)
                    }
                }
            }
        }
        .onAppear { reload() }
        .sheet(isPresented: $showingFolderPicker) {
            FolderPicker { url in
                showingFolderPicker = false
                let bookmark = makeBookmark(url) ?? ""
                let name = url.lastPathComponent
                let cfg = ScanConfig(name: name, folderUri: bookmark, folderName: name)
                beginScan(cfg)
            }
        }
        .alert("删除文库", isPresented: Binding(
            get: { runToDelete != nil },
            set: { if !$0 { runToDelete = nil } }
        )) {
            Button("取消", role: .cancel) { runToDelete = nil }
            Button("删除", role: .destructive) {
                if let run = runToDelete {
                    FileRepository.shared.deleteScanRun(runId: run.id)
                    reload()
                }
                runToDelete = nil
            }
        } message: {
            if let run = runToDelete {
                Text("确定要删除文库「\(run.name)」吗？该操作不可撤销，文库内的文件记录将被清除。")
            }
        }
        .alert("合并文库", isPresented: $showMergeAlert) {
            TextField("合并后的文库名称", text: $mergeNameInput)
            Button("取消", role: .cancel) { showMergeAlert = false }
            Button("合并") {
                let ids = Array(selectedRunIds)
                showMergeAlert = false
                let newId = FileRepository.shared.mergeRuns(ids, newName: mergeNameInput)
                if newId > 0 {
                    selecting = false
                    selectedRunIds.removeAll()
                    reload()
                    router.navigate(.library(runId: newId))
                } else {
                    ToastUtil.show(message: "合并失败")
                }
            }
        } message: {
            Text("将把选中的 \(selectedRunIds.count) 个文库合并为一个新文库，保留全部文件与标记/勾选状态。")
        }
    }

    private func reload() {
        DispatchQueue.global(qos: .userInitiated).async {
            let rs = FileRepository.shared.getScanRuns()
            let marked = rs.reduce(0) { $0 + FileRepository.shared.countMarkedFiles(runId: $1.id) }
            DispatchQueue.main.async {
                runs = rs
                markedFiles = marked
            }
        }
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(.fsPrimary).fsFont(.title3)
            Text(value).fsFont(.title2).fontWeight(.bold)
            Text(title).fsFont(.caption).foregroundColor(.fsSecondaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.fsSecondaryBg).cornerRadius(12)
    }

    private func methodRow(number: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .fsFont(.subheadline).fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.fsPrimary))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fsFont(.subheadline).fontWeight(.medium)
                Text(desc).fsFont(.caption).foregroundColor(.fsSecondaryLabel).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

func formatRunDate(_ ts: Int64) -> String {
    guard ts > 0 else { return "未知时间" }
    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
    return df.string(from: Date(timeIntervalSince1970: TimeInterval(ts) / 1000))
}

struct ScanProgressView: View {
    @EnvironmentObject var scan: ScanStateManager
    @EnvironmentObject var router: Router

    var body: some View {
        VStack(spacing: 22) {
            Spacer().frame(height: 20)
            Image(systemName: scan.finished ? "checkmark.circle.fill" : "doc.text.magnifyingglass")
                .fsFontSize(54)
                .foregroundColor(scan.finished ? .green : .fsPrimary)

            Text(scan.phaseText).fsFont(.headline)

            ProgressView(value: Double(scan.progress), total: 100)
                .progressViewStyle(.linear)
                .frame(maxWidth: 280)

            Text("\(scan.scannedFiles) / \(scan.totalFiles)").foregroundColor(.fsSecondaryLabel)

            if !scan.currentFile.isEmpty {
                Text(scan.currentFile)
                    .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
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
                PrimaryButton(title: "进入文库") {
                    router.navigate(.library(runId: scan.runId))
                }.frame(maxWidth: 240)
            }
            Spacer()
        }
        .padding()
        .navigationTitle("扫描中")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(scan.isScanning)
    }
}

extension ScanStateManager {
    var phaseText: String {
        if isScanning { return phase == "collecting" ? "正在收集文件…" : "正在解析文件…" }
        if finished {
            switch status {
            case "completed": return "扫描完成"
            case "stopped": return "已停止"
            case "empty": return "未找到匹配文件"
            case "error": return "扫描出错"
            default: return "完成"
            }
        }
        return "准备中"
    }
    var statusText: String {
        switch status {
        case "completed": return "共解析 \(scannedFiles) 个文件"
        case "stopped": return "已处理 \(scannedFiles) / \(totalFiles) 个文件"
        case "empty": return "所选文件夹中没有匹配的文件类型"
        case "error": return errorMsg.isEmpty ? "发生错误" : errorMsg
        default: return ""
        }
    }
}
