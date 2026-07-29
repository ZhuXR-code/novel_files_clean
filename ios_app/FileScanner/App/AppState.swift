import Foundation
import SwiftUI

/// 扫描状态（对齐 Android `ScanStateManager`，进程内单例）。
final class ScanStateManager: ObservableObject {
    static let shared = ScanStateManager()

    @Published var isScanning = false
    @Published var phase = "idle"           // idle / collecting / scanning / done
    @Published var totalFiles = 0
    @Published var collectedFiles = 0
    @Published var scannedFiles = 0
    @Published var progress = 0
    @Published var currentFile = ""
    @Published var finished = false
    @Published var status = ""              // completed / stopped / error / empty
    @Published var errorMsg = ""
    @Published var runId: Int64 = -1

    private var stopRequested = false

    func reset() {
        isScanning = false; phase = "idle"; totalFiles = 0; collectedFiles = 0
        scannedFiles = 0; progress = 0; currentFile = ""; finished = false
        status = ""; errorMsg = ""; stopRequested = false
    }

    func requestStop() { stopRequested = true }
    func shouldStop() -> Bool { stopRequested }

    func update(phase: String? = nil, total: Int? = nil, scanned: Int? = nil,
                collected: Int? = nil, current: String? = nil, progress p: Int? = nil) {
        if let phase { self.phase = phase }
        if let total { self.totalFiles = total }
        if let scanned { self.scannedFiles = scanned }
        if let collected { self.collectedFiles = collected }
        if let current { self.currentFile = current }
        if let p { self.progress = p }
    }
}

/// 最近一次扫描配置（供「重新扫描」复用）。
struct LastScanConfig {
    var folderUri: String = ""
    var fileTypes: String = "txt"
    var minSizeKb: Int = 0
    var recursive: Bool = true
    var excludedFolders: String = ""
    var configName: String = ""
    var folderName: String = ""
    var scanMode: String = "quick"
}

/// 全局导航路由（对齐 Android `NavRoutes` + NavHost）。
enum Route: Hashable {
    case home
    case library(runId: Int64)
    case configList
    case configEdit(id: Int64)
    case scanProgress
    case oneClick(runId: Int64)
    case settings
    case dupRule
    case keywordReplace
    case logViewer
    case help
    case fileDetail(id: Int64)
    case filePreview(id: Int64, all: Bool)
    case deleteConfirm(runId: Int64, ids: [Int64], physical: Bool)
    case deleteProgress(runId: Int64, ids: [Int64], physical: Bool)
}

final class Router: ObservableObject {
    static let shared = Router()
    @Published var path: [Route] = []

    func navigate(_ route: Route) { path.append(route) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }
}
