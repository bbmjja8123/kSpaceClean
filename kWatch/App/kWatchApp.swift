import SwiftUI
import AppKit
import MetricsKit
import DesignSystem

@main
struct kWatchApp: App {
    @NSApplicationDelegateAdaptor(kWatchAppDelegate.self) private var appDelegate
    @StateObject private var menuBarViewModel: MenuBarViewModel
    @StateObject private var onboardingViewModel: OnboardingViewModel
    @StateObject private var dashboardViewModel: DashboardViewModel
    @StateObject private var settingsViewModel: SettingsViewModel

    init() {
        let container = kWatchAppDelegate.shared.container
        _menuBarViewModel = StateObject(wrappedValue: MenuBarViewModel(container: container))
        _onboardingViewModel = StateObject(wrappedValue: OnboardingViewModel(preferences: container.preferences))
        _dashboardViewModel = StateObject(wrappedValue: DashboardViewModel(
            appState: container.appState,
            purchaseState: container.purchaseState,
            onboardingCompleted: container.preferences.onboardingCompleted
        ))
        _settingsViewModel = StateObject(wrappedValue: SettingsViewModel(
            preferences: container.preferences,
            scheduler: container.notificationScheduler,
            purchaseState: container.purchaseState,
            storeManager: container.storeManager,
            diagnosticsExporter: container.diagnosticsExporter
        ))

        // Refresh the Spotlight index so the menu-bar search field can
        // surface kWatch's quick actions. Safe to call on every launch;
        // `KWatchSpotlightIndexer` deletes the previous index first.
        Task { await KWatchSpotlightIndexer().reindex() }

        // Wire up multi-icon mode: the AppKit controller owns one status
        // item per metric and the shared router opens the dashboard from
        // AppKit contexts (status-item popovers). The `openWindow` action is
        // captured later by `MenuBarContent`'s `onAppear`.
        kWatchAppDelegate.shared.configureMultiIcon(
            settings: settingsViewModel,
            menuBar: menuBarViewModel,
            appState: container.appState,
            purchaseState: container.purchaseState,
            onOpenSettings: { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) },
            onOpenHistory: { AppWindowRouter.openDashboardWindow(); container.appState.navigate(to: .history) },
            onOpenProcesses: { AppWindowRouter.openDashboardWindow(); container.appState.navigate(to: .processes) },
            onOpenAlerts: { AppWindowRouter.openDashboardWindow(); container.appState.navigate(to: .alerts) },
            onOpenPaywall: { AppWindowRouter.openDashboardWindow(); container.appState.navigate(to: .history) }
        )
    }

    /// The metric the `MenuBarExtra` label renders. In multi-icon mode the
    /// status bar shows one item per metric: the SwiftUI extra covers the
    /// FIRST metric in `menuBarOrder` and `MultiIconStatusItemController`
    /// covers the rest, so the first item is not duplicated.
    private var labelKind: MetricKind {
        settingsViewModel.perMetricMenuBar
            ? (settingsViewModel.menuBarOrder.first ?? .cpu)
            : .cpu
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(viewModel: menuBarViewModel, appState: appState, purchaseState: purchaseState)
                .environmentObject(menuBarViewModel)
                .task {
                    menuBarViewModel.start()
                }
        } label: {
            MenuBarIcons.statusIcon(
                kind: labelKind,
                style: menuBarViewModel.iconStyle,
                values: menuBarViewModel.cpuHistory,
                currentValue: menuBarViewModel.cpuPercent,
                unit: "%"
            )
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
            SettingsView(
                viewModel: settingsViewModel,
                onCloseRequested: {
                    if let window = NSApp.windows.first(where: { $0.title == "Settings" }) {
                        window.close()
                    }
                }
            )
        }
        .windowResizability(.contentSize)
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
    @StateObject private var paywallViewModel: PaywallViewModel
    @State private var showPaywallSheet = false
    @Environment(\.openWindow) private var openWindow

    init(viewModel: MenuBarViewModel, appState: AppState, purchaseState: PurchaseState) {
        self.viewModel = viewModel
        self.appState = appState
        self.purchaseState = purchaseState
        let container = kWatchAppDelegate.shared.container
        _paywallViewModel = StateObject(wrappedValue: PaywallViewModel(
            storeManager: container.storeManager,
            purchaseState: container.purchaseState
        ))
    }

    var body: some View {
        MenuBarView(
            viewModel: viewModel,
            appState: appState,
            purchaseState: purchaseState,
            onOpenDashboard: { openWindow(id: "dashboard") },
            onOpenSettings: { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) },
            onOpenHistory: { openWindow(id: "dashboard"); appState.navigate(to: .history) },
            onOpenProcesses: { openWindow(id: "dashboard"); appState.navigate(to: .processes) },
            onOpenAlerts: { openWindow(id: "dashboard"); appState.navigate(to: .alerts) },
            onOpenPaywall: { showPaywallSheet = true }
        )
        .onAppear {
            // Capture the SwiftUI `openWindow` action so the AppKit
            // status items can open the dashboard via AppWindowRouter.
            AppWindowRouter.openDashboard = { _ in
                openWindow(id: "dashboard")
            }
        }
        .sheet(isPresented: $showPaywallSheet) {
            PaywallView(
                viewModel: paywallViewModel,
                onDismiss: { showPaywallSheet = false }
            )
        }
    }
}

/// Wraps `DashboardView` so the onboarding button can access `openWindow`,
/// and shows the StoreKit-backed `PaywallView` when Pro features are
/// gated by the dashboard.
private struct DashboardSceneContent: View {
    @ObservedObject var viewModel: DashboardViewModel
    @StateObject private var historyViewModel: HistoryViewModel
    @StateObject private var processesViewModel: ProcessesViewModel
    @StateObject private var alertsViewModel: AlertsViewModel
    @StateObject private var paywallViewModel: PaywallViewModel
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
        _alertsViewModel = StateObject(wrappedValue: AlertsViewModel(
            repository: container.alertRepository,
            scheduler: container.notificationScheduler,
            appState: container.appState,
            purchaseState: container.purchaseState
        ))
        _paywallViewModel = StateObject(wrappedValue: PaywallViewModel(
            storeManager: container.storeManager,
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
            case .alerts:
                AlertsView(
                    viewModel: alertsViewModel,
                    onBack: { viewModel.navigateToDashboard() }
                )
            default:
                dashboardView
            }
        }
        .sheet(isPresented: $showPaywallSheet) {
            PaywallView(
                viewModel: paywallViewModel,
                onDismiss: { showPaywallSheet = false }
            )
        }
    }

    private var dashboardView: some View {
        DashboardView(
            viewModel: viewModel,
            onOpenOnboarding: { openWindow(id: "onboarding") },
            onOpenPaywall: { showPaywallSheet = true }
        )
    }
}
