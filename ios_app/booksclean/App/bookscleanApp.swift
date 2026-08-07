import SwiftUI

@main
struct bookscleanApp: App {
    @StateObject private var preferences = Preferences.shared
    @StateObject private var router = Router.shared
    @StateObject private var scan = ScanStateManager.shared

    init() {
        LogUtil.i("App", "应用启动初始化：preferences=\(ObjectIdentifier(Preferences.shared)), unlocked=\(preferences.unlocked), privacy=\(preferences.privacyAgreed)")
    }

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
                            LogUtil.i("App", "未解锁，开始校验买断状态（恢复/换设备自动解锁）")
                            await IAPManager.observeTransactions()
                            await IAPManager.refreshUnlockedState()
                            LogUtil.i("App", "买断状态校验完成 unlocked=\(preferences.unlocked)")
                        }
                }
            } else {
                let _ = LogUtil.i("App", "首次启动，显示隐私协议")
                PrivacyPolicyView(
                    showActions: true,
                    onAgree: { preferences.privacyAgreed = true },
                    onDisagree: { exit(0) }
                )
            }
        }
    }
}
