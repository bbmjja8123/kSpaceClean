import SwiftUI
import WidgetKit

@main
struct kUninstallApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var menuBarController = MenuBarController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(coordinator)
                .preferredColorScheme(.dark)
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
        }
    }
}
