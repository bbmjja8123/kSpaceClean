import SwiftUI
import WidgetKit

@main
struct kFreshApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var coordinator = AppCoordinator()
    private let menuBarController = MenuBarController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(coordinator)
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
