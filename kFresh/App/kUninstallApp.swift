import SwiftUI
import WidgetKit

@main
struct kFreshApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var services = AppServices()
    private let menuBarController = MenuBarController()

    /// Honors the `-kFreshTestPro <0|1>` launch argument used by the Pro-gate
    /// UI tests: writing the shared override key makes ``StoreManager`` start
    /// in the requested Pro state before any view is built.
    init() {
        if StoreManager.parseTestProArgument(ProcessInfo.processInfo.arguments) {
            UserDefaults.standard.set(true, forKey: StoreManager.testOverrideKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(coordinator)
                .environmentObject(services)
                .onOpenURL { url in coordinator.handleDeepLink(url) }
                .onAppear {
                    coordinator.appState = appState
                    menuBarController.setup()
                    WidgetCenter.shared.reloadAllTimelines()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 960, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("关于 kFresh") {
                    coordinator.showAbout = true
                }
            }
        }
    }
}
