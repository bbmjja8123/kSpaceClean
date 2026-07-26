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
                viewModel: dashboardViewModel
            )
        }
        .defaultSize(width: 720, height: 480)

        Window("Welcome to kWatch", id: "onboarding") {
            OnboardingView(
                viewModel: onboardingViewModel,
                onCloseRequested: {
                    dashboardViewModel.dismissOnboardingBanner()
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

/// Wraps `DashboardView` so the onboarding button can access `openWindow`,
/// and provides a temporary paywall sheet that Task 18 will replace with
/// the real `PaywallView`.
private struct DashboardSceneContent: View {
    @ObservedObject var viewModel: DashboardViewModel
    @StateObject private var historyViewModel: HistoryViewModel
    @StateObject private var processesViewModel: ProcessesViewModel
    @State private var showPaywallSheet = false
    @Environment(\.openWindow) private var openWindow

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
        let container = kWatchAppDelegate.shared.container
        _historyViewModel = StateObject(wrappedValue: HistoryViewModel(
            repository: container.historyRepository,
            purchaseState: container.purchaseState
        ))
        _processesViewModel = StateObject(wrappedValue: ProcessesViewModel(
            processMonitor: container.processMonitor,
            purchaseState: container.purchaseState
        ))
    }

    var body: some View {
        Group {
            switch viewModel.navigation {
            case .dashboard:
                dashboardView
            case .history:
                HistoryView(
                    viewModel: historyViewModel,
                    onBack: { viewModel.navigateToDashboard() },
                    onOpenPaywall: { showPaywallSheet = true }
                )
            case .processes:
                ProcessesView(
                    viewModel: processesViewModel,
                    onBack: { viewModel.navigateToDashboard() },
                    onOpenPaywall: { showPaywallSheet = true }
                )
            default:
                dashboardView
            }
        }
        .sheet(isPresented: $showPaywallSheet) {
            temporaryPaywall
        }
    }

    private var dashboardView: some View {
        DashboardView(
            viewModel: viewModel,
            onOpenOnboarding: { openWindow(id: "onboarding") },
            onOpenPaywall: { showPaywallSheet = true }
        )
    }

    /// Temporary product explanation. Task 18 replaces this with StoreKit-backed `PaywallView`.
    private var temporaryPaywall: some View {
        VStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)

            Text("kWatch Pro")
                .font(.title)
                .fontWeight(.bold)

            Text("Unlock history, custom alerts, platform integrations, and advanced sensors where this Mac supports them.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("$7.99 one-time purchase. Sensor availability depends on Mac hardware.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("Not Now") {
                showPaywallSheet = false
            }
            .keyboardShortcut(.cancelAction)
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 320)
    }
}
