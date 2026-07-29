import SwiftUI

struct OneClickCleanupView: View {
    @EnvironmentObject var router: Router
    let runId: Int64

    @State private var details: [DuplicateDetail] = []
    @State private var checkedCount = 0
    @State private var busy = false

    private var totalSize: Int64 {
        details.reduce(0) { $0 + $1.totalSize }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("勾选重复：共 \(checkedCount) 个待删文件")
                        .font(.subheadline).fontWeight(.medium)
                    Text("涉及 \(details.count) 个重复子组 · 合计 \(FormatUtil.formatSize(totalSize))")
                        .font(.caption).foregroundColor(.fsSecondaryLabel)
                }
                Spacer()
                Button { recompute() } label: { if busy { ProgressView() } else { Text("重新计算") } }
                    .disabled(busy)
            }
            .padding()

            List {
                ForEach(details) { d in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(d.title).font(.subheadline).fontWeight(.medium)
                        Text("作者: \(d.author) · \(d.fileCount) 本 · 待删 \(d.dupCount) · \(FormatUtil.formatSize(d.totalSize))")
                            .font(.caption).foregroundColor(.fsSecondaryLabel)
                    }
                }
            }
            .listStyle(.plain)

            PrimaryButton(title: "开始删除（\(checkedCount) 个）") {
                let ids = FileRepository.shared.getCheckedIds(runId: runId)
                router.navigate(.deleteConfirm(runId: runId, ids: ids, physical: true))
            }
            .padding()
            .disabled(checkedCount == 0)
        }
        .navigationTitle("一键清理")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("规则") { router.navigate(.dupRule) }
            }
        }
        .onAppear { recompute() }
    }

    private func recompute() {
        busy = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                FileRepository.shared.selectDuplicateIds(runId: runId)
                return (FileRepository.shared.getDupDetails(runId: runId),
                        FileRepository.shared.getCheckedCount(runId: runId))
            }.value
            await MainActor.run {
                details = result.0
                checkedCount = result.1
                busy = false
            }
        }
    }
}
