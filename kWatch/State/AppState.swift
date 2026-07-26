import Foundation
import Combine
import MetricsKit

/// UI-owned, main-actor-isolated state for the app shell.
///
/// Holds the latest snapshot from `MetricsAggregator` and exposes navigation state.
/// Mutating `latestSnapshot` triggers view-model refreshes.
@MainActor
public final class AppState: ObservableObject {
    @Published public private(set) var latestSnapshot: MetricSnapshot?
    @Published public private(set) var navigation: NavigationDestination = .dashboard
    @Published public private(set) var isMonitoring: Bool = false

    public enum NavigationDestination: Equatable, Sendable {
        case dashboard
        case history
        case processes
        case alerts
        case settings
        case about
    }

    public init() {}

    public func update(snapshot: MetricSnapshot) {
        latestSnapshot = snapshot
    }

    public func navigate(to destination: NavigationDestination) {
        navigation = destination
    }

    public func setMonitoring(_ monitoring: Bool) {
        isMonitoring = monitoring
    }
}