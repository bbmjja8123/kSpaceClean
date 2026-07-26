import Foundation
import MetricsKit

/// Centralized dependency injection for the kWatch app.
///
/// The protocol-based container replaces a global singleton so that:
/// - Live code wires real adapters in `LiveAppContainer`.
/// - Tests inject stubs through `TestAppContainer`.
/// - Widget, Live Activity, and Intents extensions get their own per-extension
///   container (no cross-process shared state).
public protocol AppContainerProtocol: Sendable {
    var aggregator: MetricsAggregator { get }
    var appState: AppState { get }
    var purchaseState: PurchaseState { get }
    var preferences: PreferencesRepositoryProtocol { get }
    var metricsRepository: MetricsRepository { get }
    var historyRepository: HistoryRepositoryProtocol { get }
    var alertRepository: AlertRepositoryProtocol { get }
    var snapshotWriter: SnapshotWriterProtocol { get }
    // StoreManager and NotificationScheduler are added by later tasks.
}
