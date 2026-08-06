import SwiftUI
import StoreKit

/// 买断制付费墙：未解锁时展示，引导用户一次性购买永久解锁。
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var product: Product?
    @State private var priceText = "¥3.00"
    @State private var purchasing = false
    @State private var restoring = false
    @State private var message: String?

    private let features = [
        ("doc.text.magnifyingglass", "本地扫描解析", "自动解析文件名中的书名、作者、进度、来源。"),
        ("checkmark.circle", "智能去重清理", "按规则识别重复/广告/水印文件，一键清理。"),
        ("books.vertical", "合集浏览", "按书名+作者聚合，支持标记、筛选与导出。"),
        ("lock.shield", "隐私保护", "全程本地离线，文件不上传任何服务器。")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image("AppIcon")
                        .resizable()
                        .frame(width: 88, height: 88)
                        .cornerRadius(19)
                        .shadow(radius: 5)

                    VStack(spacing: 6) {
                        Text("文包整理清理助手")
                            .fsFont(.title2).fontWeight(.bold)
                        Text("一次购买 · 永久解锁全部功能")
                            .fsFont(.subheadline).foregroundColor(.fsSecondaryLabel)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(features, id: \.1) { icon, title, desc in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: icon)
                                    .foregroundColor(.fsPrimary)
                                    .frame(width: 24)
                                    .fsFont(.title3)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(title).fsFont(.subheadline).fontWeight(.medium)
                                    Text(desc).fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.fsSecondaryBg)
                    .cornerRadius(14)

                    if let message {
                        Text(message)
                            .fsFont(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Button {
                        Task { await buy() }
                    } label: {
                        if purchasing {
                            ProgressView().tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("¥3.00 永久解锁")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(purchasing || restoring)

                    Button {
                        Task { await restore() }
                    } label: {
                        if restoring {
                            ProgressView().tint(.fsPrimary)
                        } else {
                            Text("恢复购买")
                                .fsFont(.subheadline)
                        }
                    }
                    .disabled(purchasing || restoring)

                    Text("购买后可在所有设备永久使用。可随时在 App Store 账户中管理。")
                        .fsFont(.caption2).foregroundColor(.fsSecondaryLabel)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("解锁全部功能")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !Preferences.shared.unlocked {
                        Button("关闭") { dismiss() }
                    }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        if let p = await IAPManager.loadProduct() {
            product = p
            priceText = p.displayPrice
        }
    }

    private func buy() async {
        purchasing = true
        message = nil
        defer { purchasing = false }
        let target: Product
        if let product { target = product }
        else if let fetched = await IAPManager.loadProduct() { target = fetched }
        else { message = "无法连接 App Store，请稍后重试。"; return }
        let ok = await IAPManager.purchase(target)
        if ok {
            dismiss()
        } else if message == nil {
            message = "购买未完成，可重试或点击「恢复购买」。"
        }
    }

    private func restore() async {
        restoring = true
        message = nil
        defer { restoring = false }
        let ok = await IAPManager.restore()
        if ok { dismiss() }
        else { message = "未找到已有购买记录。如已购买请确认使用同一 Apple ID。" }
    }
}
