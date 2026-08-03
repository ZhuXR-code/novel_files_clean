import SwiftUI

struct DeleteConfirmView: View {
    @EnvironmentObject var router: Router
    let runId: Int64
    let ids: [Int64]
    @State private var physical: Bool

    init(runId: Int64, ids: [Int64], physical: Bool = true) {
        self.runId = runId
        self.ids = ids
        _physical = State(initialValue: physical)
    }

    private var totalSize: Int64 {
        DatabaseManager.shared.sumFileSizes(ids: ids)
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

            VStack(spacing: 18) {
                Spacer().frame(height: 16)
                Image(systemName: "trash").fsFontSize(48).foregroundColor(.red)
                Text("确认删除").fsFont(.title2).fontWeight(.semibold)
                // 已选 / 共 统计（对齐安卓底部统计条）
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text("已选 \(ids.count)").fsFont(.headline).foregroundColor(.fsPrimary)
                        Text("待删除文件").fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                    }
                    Divider().frame(height: 28)
                    VStack(spacing: 2) {
                        Text(FormatUtil.formatSize(totalSize)).fsFont(.headline).foregroundColor(.fsPrimary)
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

                PrimaryButton(title: "开始删除") {
                    router.navigate(.deleteProgress(runId: runId, ids: ids, physical: physical))
                }
                Spacer()
            }
            .padding()
        }
        .navigationTitle("删除确认")
        .navigationBarTitleDisplayMode(.inline)
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
            folderURL = resolveBookmarkURL(run.folderUri)
        }
        let accessing = folderURL?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { folderURL?.stopAccessingSecurityScopedResource() } }

        var deleted = 0, failed = 0
        for (i, f) in files.enumerated() {
            if physical, let u = URL(string: f.path) {
                do { try FileManager.default.removeItem(at: u); deleted += 1 }
                catch { failed += 1; LogUtil.e("Delete", "删除失败 \(f.fileName): \(error)") }
            }
            let p = Int((i + 1) * 100 / max(files.count, 1))
            await MainActor.run { progress = p; deletedCount = deleted; failedCount = failed }
        }
        FileRepository.shared.deleteFiles(ids: ids)
        FileRepository.shared.logOperation(level: "I", tag: "Delete", message: "删除 \(deleted) 个文件（失败 \(failed)），physical=\(physical)")
        await MainActor.run {
            finished = true
            if failed > 0 { errorMsg = "\(failed) 个文件因权限或已被移动而删除失败（数据库记录已移除）" }
        }
    }
}
