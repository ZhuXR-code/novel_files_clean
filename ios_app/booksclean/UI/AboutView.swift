import SwiftUI

// MARK: - 关于（对齐安卓设置页「关于」入口）
struct AboutView: View {
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image("AppIcon")
                    .resizable()
                    .frame(width: 84, height: 84)
                    .cornerRadius(18)
                    .shadow(radius: 4)

                Text("文包整理清理助手")
                    .fsFont(.title2).fontWeight(.bold)
                Text("版本 \(appVersion)")
                    .fsFont(.subheadline).foregroundColor(.fsSecondaryLabel)

                VStack(alignment: .leading, spacing: 12) {
                    featureRow(icon: "doc.text.magnifyingglass", title: "本地扫描解析",
                               desc: "扫描文件夹，自动解析文件名中的书名、作者、进度、来源等信息。")
                    featureRow(icon: "checkmark.circle", title: "智能去重清理",
                               desc: "按勾选重复规则识别重复、广告、水印等文件，一键清理释放空间。")
                    featureRow(icon: "books.vertical", title: "合集浏览",
                               desc: "按书名+作者聚合浏览，支持标记、筛选、全文预览与导出。")
                    featureRow(icon: "lock.shield", title: "隐私保护",
                               desc: "所有扫描与解析均在本地完成，文件不会上传到任何服务器。")
                }
                .padding()
                .background(Color.fsSecondaryBg)
                .cornerRadius(14)

                Text("本应用完全离线运行，不收集任何个人信息。")
                    .fsFont(.caption).foregroundColor(.fsSecondaryLabel)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func featureRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.fsPrimary)
                .frame(width: 24)
                .fsFont(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fsFont(.subheadline).fontWeight(.medium)
                Text(desc).fsFont(.caption).foregroundColor(.fsSecondaryLabel).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
