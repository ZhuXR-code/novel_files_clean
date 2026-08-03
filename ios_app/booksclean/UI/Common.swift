import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - iPad 适配公共工具

/// 当前设备是否为 iPad（含用 iPad 布局的 Mac Catalyst）。
/// 用于在大屏上切换多列网格、约束内容最大宽度等布局策略。
var isPad: Bool {
    UIDevice.current.userInterfaceIdiom == .pad
}

/// 根据可用宽度返回自适应的网格列数（用于文库列表 / 合集的 LazyVGrid）。
/// - Parameter width: 容器可用宽度（points）。
/// - Parameter minItemWidth: 单列最小宽度，默认 360。
func adaptiveColumns(for width: CGFloat, minItemWidth: CGFloat = 360) -> Int {
    guard width > 0 else { return 1 }
    let cols = Int((width + 12) / (minItemWidth + 12))
    return max(1, min(cols, 4))
}

/// 约束内容最大宽度并水平居中，避免大屏（iPad）上文字/卡片被拉伸过宽。
/// iPhone 上不限制（铺满），iPad 上限制为 contentMaxWidth 并居中。
struct MaxWidthContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var maxWidth: CGFloat = 720
    var applyPad: Bool = true

    var body: some View {
        if isPad {
            content()
                .frame(maxWidth: maxWidth)
                .padding(.horizontal, applyPad ? 20 : 0)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            content()
        }
    }
}


/// 文件夹选择器（iOS 文档选择器，用于挑选待扫描目录，等价于 Android 端 SAF 选目录）。
struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        vc.delegate = context.coordinator
        vc.allowsMultipleSelection = false
        return vc
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}

/// 生成安全作用域书签（base64），供后续重新访问该文件夹。
/// 注意：iOS 上不能用 .withSecurityScope（macOS 专属），文档选择器返回的 URL 用空 options 即生成安全作用域书签。
func makeBookmark(_ url: URL) -> String? {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    return (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))?.base64EncodedString()
}

/// 由 base64 书签还原文件夹 URL（iOS 上 options 必须为空集合）。
/// 返回 (URL, isStale) 元组；isStale=true 表示书签已过期，该 URL 无法用于 startAccessingSecurityScopedResource。
func resolveBookmarkURL(_ base64: String) -> (url: URL, isStale: Bool)? {
    guard let data = Data(base64Encoded: base64) else { return nil }
    var isStale = false
    guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
    return (url, isStale)
}

/// 触发一次扫描：先进入扫描进度页，再后台执行扫描。
func beginScan(_ config: ScanConfig) {
    Router.shared.navigate(.scanProgress)
    Task { _ = await ScanService.shared.scan(config: config) }
}

/// 通用加载/进度按钮。
struct PrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(enabled ? Color.fsPrimary : Color.fsSecondaryBg)
                .foregroundColor(enabled ? .white : .fsSecondaryLabel)
                .cornerRadius(8)
        }
        .disabled(!enabled)
    }
}
