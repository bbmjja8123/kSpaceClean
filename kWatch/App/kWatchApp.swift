import SwiftUI
import AppKit
import MetricsKit

@main
struct kWatchApp: App {
    @NSApplicationDelegateAdaptor(kWatchAppDelegate.self) private var appDelegate
    @StateObject private var menuBarViewModel: MenuBarViewModel
    @StateObject private var onboardingViewModel: OnboardingViewModel
    @StateObject private var dashboardViewModel: DashboardViewModel

    init() {
        let container = kWatchAppDelegate.shared.container
        _menuBarViewModel = StateObject(wrappedValue: MenuBarViewModel(container: container))
        _onboardingViewModel = StateObject(wrappedValue: OnboardingViewModel(preferences: container.preferences))
        _dashboardViewModel = StateObject(wrappedValue: DashboardViewModel(
            appState: container.appState,
            purchaseState: container.purchaseState,
            onboardingCompleted: container.preferences.onboardingCompleted
        ))
    }

    var body: some Scene {
        MenuBarExtra("kWatch", systemImage: "gauge.with.dots.needle.bottom.50percent") {
            MenuBarContent(viewModel: menuBarViewModel, appState: appState, purchaseState: purchaseState)
                .environmentObject(menuBarViewModel)
                .task { menuBarViewModel.start() }
        }
        .menuBarExtraStyle(.window)

        Window("kWatch Dashboard", id: "dashboard") {
            DashboardSceneContent(
                viewModel: dashboardViewModel,
                purchaseState: purchaseState
            )
        }
        .defaultSize(width: 720, height: 480)

        Window("Welcome to kWatch", id: "onboarding") {
            OnboardingView(
                viewModel: onboardingViewModel,
                onCloseRequested: {
                    if let window = NSApp.windows.first(where: { $0.title == "Welcome to kWatch" }) {
                        window.close()
                    }
                }
            )
        }
        .defaultSize(width: 520, height: 420)
        .windowResizability(.contentSize)

        Settings {
            // Placeholder; Task 17 implements the real Settings window.
            Text("kWatch Settings")
        }
    }

    private var appState: AppState { kWatchAppDelegate.shared.container.appState }
    private var purchaseState: PurchaseState { kWatchAppDelegate.shared.container.purchaseState }
}

/// Wraps `MenuBarView` so navigation closures can access the `openWindow`
/// environment action (only available inside a `View`, not a `Scene`).
private struct MenuBarContent: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @ObservedObject var appState: AppState
    @ObservedObject var purchaseState: PurchaseState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarView(
            viewModel: viewModel,
            appState: appState,
            purchaseState: purchaseState,
            onOpenDashboard: { openWindow(id: "dashboard") },
            onOpenSettings: { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) },
            onOpenHistory: { openWindow(id: "dashboard"); appState.navigate(to: .history) },
            onOpenProcesses: { openWindow(id: "dashboard"); appState.navigate(to: .processes) },
            onOpenAlerts: { openWindow(id: "dashboard"); appState.navigate(to: .alerts) }
        )
    }
}

/// Wraps `DashboardView` so the onboarding button can access `openWindow`.
private struct DashboardSceneContent: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var purchaseState: PurchaseState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        DashboardView(
            viewModel: viewModel,
            purchaseState: purchaseState,
            onOpenOnboarding: { openWindow(id: "onboarding") }
        )
    }
}