import SwiftUI

struct HomeView: View {
    @EnvironmentObject var router: Router
    @State private var runs: [ScanRun] = []
    @State private var showingFolderPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                FSSection("快速开始") {
                    VStack(spacing: 10) {
                        PrimaryButton(title: "选择文件夹开始扫描") { showingFolderPicker = true }
                        Button { router.navigate(.configList) } label: {
                            Text("扫描配置").frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(Color.fsTertiaryBg).cornerRadius(10)
                        }
                    }
                }

                FSSection("文库列表") {
                    if runs.isEmpty {
                        Text("暂无扫描记录，点击上方按钮选择文件夹开始。")
                            .foregroundColor(.fsSecondaryLabel).padding(.vertical, 8)
                    } else {
                        ForEach(runs) { run in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(run.folderName.isEmpty ? run.name : run.folderName)
                                        .font(.subheadline).fontWeight(.medium)
                                    Text("\(run.fileCount) 个文件 · \(formatRunDate(run.createdAt))")
                                        .font(.caption).foregroundColor(.fsSecondaryLabel)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundColor(.fsSecondaryLabel)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { router.navigate(.library(runId: run.id)) }
                            .contextMenu {
                                // 注意：swipeActions 只在 List 中生效，这里是 ScrollView，故用长按菜单
                                Button(role: .destructive) {
                                    FileRepository.shared.deleteScanRun(runId: run.id)
                                    reload()
                                } label: { Label("删除文库", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("文包清理助手")
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
    }

    private func reload() { runs = FileRepository.shared.getScanRuns() }
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
                .font(.system(size: 54))
                .foregroundColor(scan.finished ? .green : .fsPrimary)

            Text(scan.phaseText).font(.headline)

            ProgressView(value: Double(scan.progress), total: 100)
                .progressViewStyle(.linear)
                .frame(maxWidth: 280)

            Text("\(scan.scannedFiles) / \(scan.totalFiles)").foregroundColor(.fsSecondaryLabel)

            if !scan.currentFile.isEmpty {
                Text(scan.currentFile)
                    .font(.caption).foregroundColor(.fsSecondaryLabel)
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
