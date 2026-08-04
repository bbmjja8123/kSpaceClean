import SwiftUI
import Combine

@main
struct kSiftApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var store = StoreManager()

    /// Thread-safe mirror of `store.isPaidUser` for the background
    /// `ScanOrchestrator` / `IncrementalIndex` actors. Pushed from
    /// `store.$isPaidUser` in `body` so the actors never have to touch
    /// MainActor state directly.
    @State private var paidFlag = PaidUserFlag()

    /// Retains the Combine subscription so the mirror stays alive for the
    /// lifetime of the app process.
    @State private var paidSubscription: AnyCancellable?
    @State private var menuBarController: MenuBarController?

    init() {
        // The App Intents run in the app process when openAppWhenRun=true;
        // give them a handle to AppState so they can publish results into
        // the same store the UI observes. The intents themselves are
        // macOS 14+, so guard the assignment for the macOS 13 path.
        if #available(macOS 14, *) {
            ScanDirectoryIntent.appState = appState
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(coordinator)
                .environmentObject(store)
                .environment(\.paidUserFlag, paidFlag)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    coordinator.handleDeepLink(url)
                }
                .onAppear {
                    coordinator.appState = appState
                    if menuBarController == nil {
                        NSApp.setActivationPolicy(.accessory)
                        menuBarController = MenuBarController(coordinator: coordinator, appState: appState)
                    }
                    if #available(macOS 14, *) {
                        ScanDirectoryIntent.appState = appState
                    }
                    coordinator.startObservingFinderScanRequests()
                    // Drain a pending Finder Sync request that arrived while
                    // the app was closed (the extension's write to shared
                    // UserDefaults survives across launches).
                    coordinator.drainPendingFinderScanRequest()

                    // Seed the mirror and start streaming future updates so
                    // background actors see the current paid status without
                    // crossing actor boundaries.
                    paidFlag.set(store.isPaidUser)
                    if paidSubscription == nil {
                        paidSubscription = store.$isPaidUser
                            .sink { paid in paidFlag.set(paid) }
                    }
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