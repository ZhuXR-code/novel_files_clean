import SwiftUI

@main
struct bookscleanApp: App {
    @StateObject private var preferences = Preferences.shared
    @StateObject private var router = Router.shared
    @StateObject private var scan = ScanStateManager.shared

    init() {
        LogUtil.i("App", "应用启动初始化：preferences=\(ObjectIdentifier(Preferences.shared)), privacy=\(preferences.privacyAgreed)")
    }

    var body: some Scene {
        WindowGroup {
            if preferences.privacyAgreed {
                // 付费 App：用户下载前已付费，下载即用全部功能，无需内购校验
                ContentView()
                    .environmentObject(router)
                    .environmentObject(preferences)
                    .environmentObject(scan)
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
