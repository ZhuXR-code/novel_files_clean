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
/// 20w+ 量级下分页加载：全量 ids 仅保留 id 数组（极小），文件详情按页（200）从数据库取，避免一次性把全部文件塞进 List 导致 OOM。
struct OneClickReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let runId: Int64
    let onSaved: () -> Void

    private let pageSize = 200

    @State private var allIds: [Int64] = []
    @State private var items: [ScannedFile] = []
    @State private var draft: Set<Int64> = []
    @State private var loading = true
    @State private var loadingMore = false
    @State private var reachedEnd = false

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
                    Button("全选") { draft = Set(allIds) }
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
                    List {
                        ForEach(items) { f in
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
                            .onAppear { loadMoreIfNeeded(current: f.id) }
                        }
                        if loadingMore {
                            HStack { Spacer(); ProgressView(); Spacer() }
                                .listRowSeparator(.hidden)
                        }
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

    /// 加载全部已勾选 id（分批，仅 id 数组），并取首页文件详情。
    private func load() {
        let ids = FileRepository.shared.getCheckedIds(runId: runId)
        allIds = ids
        draft = Set(ids)
        appendPage()
        loading = false
    }

    /// 按需追加下一页文件详情（每页 pageSize 个）。
    private func appendPage() {
        guard !loadingMore, !reachedEnd else { return }
        let start = items.count
        guard start < allIds.count else { reachedEnd = true; return }
        let end = min(start + pageSize, allIds.count)
        let slice = Array(allIds[start..<end])
        loadingMore = true
        Task.detached(priority: .userInitiated) {
            let page = FileRepository.shared.getByIds(slice)
            Task { @MainActor in
                self.items.append(contentsOf: page)
                self.loadingMore = false
                if self.items.count >= self.allIds.count { self.reachedEnd = true }
            }
        }
    }

    private func loadMoreIfNeeded(current: Int64) {
        guard let last = items.last else { return }
        if current == last.id { appendPage() }
    }

    private func save() {
        // 仅对发生变化的文件回写，避免 20w 全量 UPDATE。
        let checkedNow = draft
        let checkedPrev = Set(allIds)
        let toUncheck = checkedPrev.subtracting(checkedNow)
        let toCheck = checkedNow.subtracting(checkedPrev)
        if !toUncheck.isEmpty { FileRepository.shared.updateChecked(ids: Array(toUncheck), checked: false) }
        if !toCheck.isEmpty { FileRepository.shared.updateChecked(ids: Array(toCheck), checked: true) }
        onSaved()
        dismiss()
    }
}
