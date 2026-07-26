import Foundation
import Combine
import MetricsKit

/// Drives the dashboard screen, building card view models from the latest
/// `MetricSnapshot` and the current Pro entitlement.
///
/// The view model subscribes to `AppState.$latestSnapshot` and
/// `PurchaseState.$isPro` so that cards automatically update when a new
/// sampling cycle completes or the user upgrades/downgrades.
@MainActor
public final class DashboardViewModel: ObservableObject {
    // MARK: - Published state

    /// One card per known metric kind, built from the latest snapshot.
    @Published public private(set) var cards: [MetricCardViewModel] = []

    /// The kind the user tapped for detail inspection (or `nil`).
    @Published public var selectedKind: MetricKind? = nil

    /// Whether the user has not yet completed onboarding.
    @Published public private(set) var showOnboardingBanner: Bool = false

    /// Latest snapshot mirrored from the app state for dashboard consumers.
    @Published public private(set) var latestSnapshot: MetricSnapshot?

    /// Whether the coordinator is actively sampling metrics.
    @Published public private(set) var isMonitoring: Bool = false

    /// Current destination in the dashboard window.
    @Published public private(set) var navigation: AppState.NavigationDestination = .dashboard

    // MARK: - Dependencies

    private let appState: AppState
    private let purchaseState: PurchaseState
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    public init(
        appState: AppState,
        purchaseState: PurchaseState,
        onboardingCompleted: Bool = false
    ) {
        self.appState = appState
        self.purchaseState = purchaseState
        self.showOnboardingBanner = !onboardingCompleted
        self.latestSnapshot = appState.latestSnapshot
        self.isMonitoring = appState.isMonitoring
        self.navigation = appState.navigation

        // Observe snapshot changes.
        appState.$latestSnapshot
            .sink { [weak self] snapshot in
                self?.latestSnapshot = snapshot
                self?.rebuildCards(from: snapshot)
            }
            .store(in: &cancellables)

        appState.$isMonitoring
            .sink { [weak self] isMonitoring in
                self?.isMonitoring = isMonitoring
            }
            .store(in: &cancellables)

        appState.$navigation
            .sink { [weak self] navigation in
                self?.navigation = navigation
            }
            .store(in: &cancellables)

        // Observe Pro entitlement changes so lock state updates immediately.
        purchaseState.$isPro
            .sink { [weak self] _ in
                self?.rebuildCards(from: self?.appState.latestSnapshot)
            }
            .store(in: &cancellables)

        // Initial build (even without a snapshot, cards default to unavailable).
        rebuildCards(from: appState.latestSnapshot)
    }

    // MARK: - Actions

    /// Dismiss the onboarding banner for the remainder of this session.
    public func dismissOnboardingBanner() {
        showOnboardingBanner = false
    }

    /// Navigate to the history view.
    public func navigateToHistory() {
        appState.navigate(to: .history)
    }

    /// Navigate to the processes view.
    public func navigateToProcesses() {
        appState.navigate(to: .processes)
    }

    /// Navigate to the alerts view.
    public func navigateToAlerts() {
        appState.navigate(to: .alerts)
    }

    // MARK: - Card building

    /// Rebuild the `cards` array from a snapshot, preserving selection if
    /// the selected kind still exists.
    private func rebuildCards(from snapshot: MetricSnapshot?) {
        let isPro = purchaseState.isPro
        let newCards: [MetricCardViewModel] = MetricKind.allCases.map { kind in
            let value: MetricValue
            let availability: MetricAvailability

            if let snapshot {
                value = snapshot.values[kind] ?? .unavailable(.unsupported("No data"))
                availability = snapshot.availability[kind] ?? .unavailable(reason: "No data")
            } else {
                value = .unavailable(.unsupported("Waiting for data"))
                availability = .unavailable(reason: "Waiting for data")
            }

            return MetricCardViewModel(
                kind: kind,
                value: value,
                availability: availability,
                isPro: isPro
            )
        }

        // Preserve selection if the selected kind still exists in new cards.
        if let selectedKind, !newCards.contains(where: { $0.kind == selectedKind }) {
            self.selectedKind = nil
        }

        cards = newCards
    }
}
