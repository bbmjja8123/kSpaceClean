import SwiftUI
import CoreData

@main
struct kWiseApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var menuBarManager = MenuBarManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(coordinator)
                .environment(\.managedObjectContext, CoreDataStack.shared.viewContext)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    coordinator.handleDeepLink(url)
                }
                .onAppear {
                    coordinator.appState = appState
                    menuBarManager.setup()
                    installMetricKitReceiver()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 960, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }

    /// Activates the TestFlight feedback hook (Task D2).
    /// The receiver writes any MetricKit-vended crash reports to
    /// `~/Library/Application Support/kWise/metric-kit/` on macOS 14+
    /// and is a no-op on macOS 13.
    private func installMetricKitReceiver() {
        if #available(macOS 14.0, *) {
            let receiver = MetricKitReceiver()
            receiver.subscribe()
        }
    }
}
