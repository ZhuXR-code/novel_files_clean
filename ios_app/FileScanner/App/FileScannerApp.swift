import SwiftUI

@main
struct FileScannerApp: App {
    @StateObject private var preferences = Preferences.shared
    @StateObject private var router = Router.shared
    @StateObject private var scan = ScanStateManager.shared

    var body: some Scene {
        WindowGroup {
            if preferences.privacyAgreed {
                ContentView()
                    .environmentObject(router)
                    .environmentObject(preferences)
                    .environmentObject(scan)
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
