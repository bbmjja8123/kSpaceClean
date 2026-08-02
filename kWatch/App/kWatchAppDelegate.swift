import AppKit
import Combine

/// Bridges AppKit lifecycle events to the shared app coordinator.
@MainActor
public final class kWatchAppDelegate: NSObject, NSApplicationDelegate {
    public static let shared = kWatchAppDelegate()

    public let container: LiveAppContainer
    private var coordinator: AppCoordinator?

    /// The per-metric status-item controller for multi-icon mode, created by
    /// `configureMultiIcon` on app launch. `nil` until configured.
    public private(set) var multiIconController: MultiIconStatusItemController?

    private override init() {
        self.container = LiveAppContainer()
        super.init()
    }

    /// Wire the multi-icon status-item controller to the settings-driven
    /// metric set and order. Safe to call once at launch; the Combine
    /// subscription lives inside `controller.cancellables`.
    public func configureMultiIcon(
        settings: SettingsViewModel,
        menuBar: MenuBarViewModel,
        appState: AppState,
        purchaseState: PurchaseState,
        onOpenSettings: @escaping () -> Void,
        onOpenHistory: @escaping () -> Void,
        onOpenProcesses: @escaping () -> Void,
        onOpenAlerts: @escaping () -> Void,
        onOpenPaywall: (() -> Void)? = nil
    ) {
        let controller = MultiIconStatusItemController(
            menuBarViewModel: menuBar,
            appState: appState,
            purchaseState: purchaseState,
            onOpenSettings: onOpenSettings,
            onOpenHistory: onOpenHistory,
            onOpenProcesses: onOpenProcesses,
            onOpenAlerts: onOpenAlerts,
            onOpenPaywall: onOpenPaywall
        )
        multiIconController = controller

        // Strict-concurrency-safe Combine mirror of the settings flags: keep
        // the controller's metric set in sync whenever the user toggles
        // multi-icon mode or drags the order.
        settings.$perMetricMenuBar
            .combineLatest(settings.$menuBarOrder)
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled, order in
                guard let self else { return }
                if enabled {
                    controller.setMetrics(Array(order.dropFirst()))
                } else {
                    controller.setMetrics([])
                }
            }
            .store(in: &controller.cancellables)
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator(container: container)
        self.coordinator = coordinator
        coordinator.start()

        // Subscribe to MetricKit so daily performance summaries and any
        // crash/hang payloads are written to the App Group container.
        // MetricKitSubscriber.start() is idempotent and runs only on the
        // main actor.
        container.metricKitSubscriber.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }
}
