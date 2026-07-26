import Foundation
import MetricsKit

/// Main-actor-isolated view model for the threshold alerts feature.
///
/// Owns the alerts list read from `AlertRepositoryProtocol`, exposes CRUD and
/// toggle operations, manages the editor sheet state, and coordinates with
/// `AlertEvaluator` and `NotificationSchedulerProtocol` for notification firing.
@MainActor
public final class AlertsViewModel: ObservableObject {
    // MARK: - Published state

    /// All alerts loaded from the repository, sorted by metric kind.
    @Published public private(set) var alerts: [MetricAlert] = []

    /// The alert currently being edited in the sheet, or `nil`.
    @Published public var editingAlert: MetricAlert? = nil

    /// Whether the alert editor sheet is presented.
    @Published public var isPresentingEditor = false

    /// Whether the user has granted notification permission.
    @Published public var isNotificationsAuthorized = false

    // MARK: - Dependencies

    private let repository: AlertRepositoryProtocol
    private let scheduler: NotificationSchedulerProtocol
    private let appState: AppState
    private let purchaseState: PurchaseState

    // MARK: - Init

    public init(
        repository: AlertRepositoryProtocol,
        scheduler: NotificationSchedulerProtocol,
        appState: AppState,
        purchaseState: PurchaseState
    ) {
        self.repository = repository
        self.scheduler = scheduler
        self.appState = appState
        self.purchaseState = purchaseState
    }

    // MARK: - CRUD

    /// Reload the alerts list from the repository. Call after any mutation.
    public func refresh() {
        do {
            alerts = try repository.all()
        } catch {
            purchaseState.recordError("Failed to load alerts: \(error.localizedDescription)")
        }
    }

    /// Persist an alert (insert or update) and refresh the list.
    public func save(_ alert: MetricAlert) {
        do {
            try repository.upsert(alert)
            refresh()
            isPresentingEditor = false
            editingAlert = nil
        } catch {
            purchaseState.recordError("Failed to save alert: \(error.localizedDescription)")
        }
    }

    /// Remove an alert from the repository and refresh the list.
    public func delete(_ alert: MetricAlert) {
        do {
            try repository.delete(id: alert.id)
            refresh()
        } catch {
            purchaseState.recordError("Failed to delete alert: \(error.localizedDescription)")
        }
    }

    /// Flip the `isEnabled` flag on the given alert.
    public func toggle(_ alert: MetricAlert) {
        let updated = MetricAlert(
            id: alert.id,
            kind: alert.kind,
            op: alert.op,
            threshold: alert.threshold,
            isEnabled: !alert.isEnabled,
            cooldownSeconds: alert.cooldownSeconds,
            lastTriggeredAt: alert.lastTriggeredAt
        )
        do {
            try repository.upsert(updated)
            refresh()
        } catch {
            purchaseState.recordError("Failed to toggle alert: \(error.localizedDescription)")
        }
    }

    // MARK: - Editor sheet

    /// Prepare the editor for creating a new alert with default values.
    public func beginAdd() {
        editingAlert = MetricAlert(
            kind: .cpu,
            op: .above,
            threshold: 80,
            isEnabled: true,
            cooldownSeconds: 300
        )
        isPresentingEditor = true
    }

    /// Prepare the editor for editing an existing alert.
    public func beginEdit(_ alert: MetricAlert) {
        editingAlert = alert
        isPresentingEditor = true
    }

    /// Whether the currently edited alert is a new one (not yet persisted).
    public var isEditingNewAlert: Bool {
        guard let editing = editingAlert else { return false }
        return !alerts.contains(where: { $0.id == editing.id })
    }

    // MARK: - Notifications

    /// Request notification permission and update `isNotificationsAuthorized`.
    public func requestNotificationPermission() async {
        await scheduler.requestAuthorization()
        let status = await scheduler.authorizationStatus
        isNotificationsAuthorized = (status == .authorized || status == .provisional)
    }

    // MARK: - Evaluation

    /// Evaluate all enabled alerts against the given snapshot.
    ///
    /// Triggered alerts are passed to the scheduler for notification delivery,
    /// and their `lastTriggeredAt` timestamps are updated in the repository so
    /// that the cooldown is honored on subsequent evaluations.
    public func evaluate(snapshot: MetricSnapshot) async {
        let triggered = AlertEvaluator.evaluate(snapshot: snapshot, alerts: alerts)
        for alert in triggered {
            if let value = snapshot.values[alert.kind] {
                await scheduler.schedule(alert: alert, value: value)
            }
            do {
                try repository.recordTriggered(id: alert.id, at: Date())
            } catch {
                purchaseState.recordError(
                    "Failed to record alert trigger: \(error.localizedDescription)"
                )
            }
        }
        if !triggered.isEmpty {
            refresh()
        }
    }

    // MARK: - Default alerts

    /// Three free-tier default alerts shipped with every install.
    public static let defaultAlerts: [MetricAlert] = [
        MetricAlert(kind: .cpu, op: .above, threshold: 80, isEnabled: true, cooldownSeconds: 300),
        MetricAlert(kind: .memory, op: .above, threshold: 80, isEnabled: true, cooldownSeconds: 300),
        MetricAlert(kind: .disk, op: .above, threshold: 90, isEnabled: true, cooldownSeconds: 300)
    ]

    /// If the alerts list is empty, pre-populate with the three free defaults.
    /// Safe to call repeatedly — only inserts when the list is empty.
    public func ensureDefaults() {
        guard alerts.isEmpty else { return }
        for alert in Self.defaultAlerts {
            do {
                try repository.upsert(alert)
            } catch {
                purchaseState.recordError(
                    "Failed to create default alert: \(error.localizedDescription)"
                )
            }
        }
        refresh()
    }
}
