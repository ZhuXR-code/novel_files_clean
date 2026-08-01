import SwiftUI

struct OneClickCleanupView: View {
    @EnvironmentObject var router: Router
    let runId: Int64

    @State private var details: [DuplicateDetail] = []
    @State private var checkedCount = 0
    @State private var busy = false
    @State private var showReview = false

    private var totalSize: Int64 {
        details.reduce(0) { $0 + $1.totalSize }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("勾选重复：共 \(checkedCount) 个待删文件")
                        .fsFont(.subheadline).fontWeight(.medium)
                    Text("涉及 \(details.count) 个重复子组 · 合计 \(FormatUtil.formatSize(totalSize))")
                        .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                }
                Spacer()
                Button { recompute() } label: { if busy { ProgressView() } else { Text("重新计算") } }
                    .disabled(busy)
            }
            .padding()

            List {
                if details.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .fsFontSize(40).foregroundColor(.fsPrimary)
                        Text("没有发现重复文件")
                            .fsFont(.headline)
                        Text("当前文库未匹配到可清理的重复项，或重复规则未勾选。")
                            .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(details) { d in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(d.title).fsFont(.subheadline).fontWeight(.medium)
                            Text("作者: \(d.author) · \(d.fileCount) 本 · 待删 \(d.dupCount) · \(FormatUtil.formatSize(d.totalSize))")
                                .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                        }
                    }
                }
            }
            .listStyle(.plain)

            // 确认区（对齐安卓 confirm 阶段：警示 + 查看清单 + 确认删除）
            VStack(spacing: 8) {
                Text("删除后文件将从设备移除，且无法恢复，请先核对清单。")
                    .fsFont(.caption).foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    showReview = true
                } label: {
                    Text("查看待删清单（\(checkedCount) 个）").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(checkedCount == 0)

                PrimaryButton(title: "确认删除（\(checkedCount) 个）") {
                    let ids = FileRepository.shared.getCheckedIds(runId: runId)
                    router.navigate(.deleteConfirm(runId: runId, ids: ids, physical: true))
                }
                .disabled(checkedCount == 0)
            }
            .padding()
        }
        .navigationTitle("一键清理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("规则") { router.navigate(.dupRule) }
            }
        }
        .onAppear { recompute() }
        .sheet(isPresented: $showReview) {
            OneClickReviewSheet(runId: runId) { recompute() }
        }
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

/// 待删清单复核（对齐安卓 review 阶段）：逐条勾选 / 全选 / 全不选，保存后回写 checked 状态。
struct OneClickReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let runId: Int64
    let onSaved: () -> Void

    @State private var items: [ScannedFile] = []
    @State private var draft: Set<Int64> = []
    @State private var loading = true

    private var draftSize: Int64 {
        items.filter { draft.contains($0.id) }.reduce(0) { $0 + $1.fileSize }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("以下是本次将被删除的文件，取消勾选可保留该文件。")
                    .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.top, 8)

                HStack(spacing: 10) {
                    Button("全选") { draft = Set(items.map { $0.id }) }
                        .buttonStyle(.bordered)
                    Button("全不选") { draft = [] }
                        .buttonStyle(.bordered)
                    Spacer()
                    Text("已选 \(draft.count) · \(FormatUtil.formatSize(draftSize))")
                        .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                }
                .padding(.horizontal).padding(.vertical, 8)

                if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                    Text("暂无待删文件").fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(items) { f in
                        Button {
                            if draft.contains(f.id) { draft.remove(f.id) } else { draft.insert(f.id) }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: draft.contains(f.id) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(draft.contains(f.id) ? .fsPrimary : .fsSecondaryLabel)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.fileName).fsFont(.caption).fontWeight(.medium)
                                        .foregroundColor(.primary).lineLimit(2)
                                    Text("\(f.title)　\(f.author)　\(FormatUtil.formatSize(f.fileSize))")
                                        .fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("待删清单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("返回") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存(\(draft.count))") { save() }
                }
            }
            .onAppear { load() }
        }
    }

    private func load() {
        let ids = FileRepository.shared.getCheckedIds(runId: runId)
        items = FileRepository.shared.getByIds(ids)
        draft = Set(ids)
        loading = false
    }

    private func save() {
        let all = items.map { $0.id }
        let keep = all.filter { !draft.contains($0) }
        // 取消勾选的文件恢复为不删除，其余保持勾选
        FileRepository.shared.updateChecked(ids: keep, checked: false)
        FileRepository.shared.updateChecked(ids: Array(draft), checked: true)
        onSaved()
        dismiss()
    }
}
