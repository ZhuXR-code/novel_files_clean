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
                    case .oneClick(let runId): OneClickCleanupView(runId: runId)
                    case .settings: SettingsView()
                    case .dupRule: DupRuleView()
                    case .keywordReplace: KeywordReplaceView()
                    case .logViewer: LogViewerView()
                    case .help: HelpView()
                    case .fileDetail(let id): FileDetailView(fileId: id)
                    case .filePreview(let id, let all): FilePreviewView(fileId: id, all: all)
                    case .deleteConfirm(let runId, let ids, let physical): DeleteConfirmView(runId: runId, ids: ids, physical: physical)
                    case .deleteProgress(let runId, let ids, let physical): DeleteProgressView(runId: runId, ids: ids, physical: physical)
                    }
                }
        }
        .preferredColorScheme(prefs.themeMode == "dark" ? .dark : prefs.themeMode == "light" ? .light : nil)
    }
}
