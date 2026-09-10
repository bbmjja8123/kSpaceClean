import SwiftUI
import CoreData

@main
struct kWiseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var coordinator = AppCoordinator()
    /// Single DI root (v2.0 Phase 1). Everything process-wide — cleanup
    /// engine, store manager, menu bar — lives on the graph so surfaces
    /// can't disagree (the old code had two `MenuBarManager`s and three
    /// `StoreManager`s).
    @StateObject private var graph = AppGraph()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(coordinator)
                .environment(\.appGraph, graph)
                .environment(\.managedObjectContext, CoreDataStack.shared.viewContext)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    coordinator.handleDeepLink(url)
                }
                .onAppear {
                    coordinator.appState = appState
                    graph.menuBarManager.setup()
                    installMetricKitReceiver()
                    // Phase 1: resolve any persisted home-folder bookmark
                    // and probe sandbox-readable dirs once per session.
                    Task { await AppScope.shared.refresh() }
                    // Phase 6: opportunistically refresh the widget feed's
                    // disk numbers (no background agent — MAS policy).
                    WidgetSnapshotSink.refreshDiskInfo()
                    // Phase 7: daily disk-usage sample (opportunistic).
                    DiskUsageSampler().sample()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1120, height: 720)
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
