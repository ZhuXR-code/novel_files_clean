import SwiftUI

@main
struct bookscleanApp: App {
    @StateObject private var preferences = Preferences.shared
    @StateObject private var router = Router.shared
    @StateObject private var scan = ScanStateManager.shared

    var body: some Scene {
        WindowGroup {
            if preferences.privacyAgreed {
                if preferences.unlocked {
                    ContentView()
                        .environmentObject(router)
                        .environmentObject(preferences)
                        .environmentObject(scan)
                } else {
                    PaywallView()
                        .environmentObject(router)
                        .environmentObject(preferences)
                        .environmentObject(scan)
                        .task {
                            // 启动即校验是否已买断（恢复/换设备自动解锁）
                            await IAPManager.observeTransactions()
                            await IAPManager.refreshUnlockedState()
                        }
                }
            } else {
                PrivacyPolicyView(
                    showActions: true,
                    onAgree: { preferences.privacyAgreed = true },
                    onDisagree: { exit(0) }
                )
            }
        }
    }
}
