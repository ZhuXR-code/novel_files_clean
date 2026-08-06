import SwiftUI

struct ContentView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var prefs: Preferences

    var body: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .home: HomeView()
                    case .library(let runId): LibraryView(runId: runId)
                    case .configList: ConfigListView()
                    case .configEdit(let id): ConfigEditView(configId: id)
                    case .scanProgress: ScanProgressView()
                    case .oneClick(let config): OneClickCleanupView(config: config)
                    case .oneClickExisting(let runId): OneClickCleanupView(runId: runId)
                    case .settings: MaxWidthContainer { SettingsView() }
                    case .dupRule: MaxWidthContainer { DupRuleView() }
                    case .keywordReplace: MaxWidthContainer { KeywordReplaceView() }
                    case .logViewer: LogViewerView()
                    case .help: MaxWidthContainer { HelpView() }
                    case .privacy: MaxWidthContainer { PrivacyPolicyView() }
                    case .about: MaxWidthContainer { AboutView() }
                    case .fileDetail(let id): MaxWidthContainer { FileDetailView(fileId: id) }
                    case .filePreview(let id, let mode): MaxWidthContainer { FilePreviewView(fileId: id, mode: mode) }
                    case .deleteConfirm(let runId, let ids, let physical): DeleteConfirmView(runId: runId, ids: ids, physical: physical)
                    case .deleteProgress(let runId, let ids, let physical): DeleteProgressView(runId: runId, ids: ids, physical: physical)
                    case .paywall: PaywallView()
                    }
                }
        }
        .preferredColorScheme(prefs.themeMode == "dark" ? .dark : prefs.themeMode == "light" ? .light : nil)
        .navigationViewStyle(.stack) // iPad 上保持单列导航，避免默认双列 master-detail
        .onAppear {
            configureNavBarAppearance()
        }
    }
}

/// 全局导航栏外观：对齐安卓顶栏（绿色加粗紧凑标题 + 与背景融合 + 底部细分隔线，minimalism）。
private func configureNavBarAppearance() {
    let accent = UIColor(named: "AccentColor") ?? UIColor.systemGreen
    let appearance = UINavigationBarAppearance()
    appearance.configureWithOpaqueBackground()
    appearance.backgroundColor = UIColor.systemBackground
    let titleFont = UIFont.boldSystemFont(ofSize: 17) // 接近安卓 TopBar 18sp 加粗
    appearance.titleTextAttributes = [.foregroundColor: accent, .font: titleFont]
    appearance.largeTitleTextAttributes = [.foregroundColor: accent, .font: UIFont.boldSystemFont(ofSize: 17)]
    appearance.shadowColor = UIColor.separator // 底部 1px 细分隔线
    UINavigationBar.appearance().standardAppearance = appearance
    UINavigationBar.appearance().scrollEdgeAppearance = appearance
    UINavigationBar.appearance().compactAppearance = appearance
}
