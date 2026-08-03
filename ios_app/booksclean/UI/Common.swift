import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
func resolveBookmarkURL(_ base64: String) -> URL? {
    guard let data = Data(base64Encoded: base64) else { return nil }
    var isStale = false
    return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
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
