import Foundation
import MetricsKit

#if canImport(ActivityKit)
import ActivityKit
#endif

/// Owns the lifecycle of kWatch Live Activities.
///
/// Activities are started on critical alerts (Pro users on macOS 14+) and
/// ended when the user dismisses or the underlying condition resolves.
///
/// The entire implementation is gated by `@available(macOS 14.0, *)` and
/// `#if canImport(ActivityKit)`:
/// macOS 13 lacks `ActivityKit`, so the coordinator cannot be defined on
/// older systems. Call sites must `if #available(macOS 14.0, *)` before
/// referencing the type.
///
/// On macOS 14+ the coordinator is an `actor` because `Activity.update`
/// and `Activity.end` are async and the same instance is reachable from
/// the alert-eval hot path and the dismiss-acknowledgement path.
@available(macOS 14.0, *)
public actor LiveActivityCoordinator {

    /// Direction of change used by the compact activity row. Mirrors
    /// `MetricActivityAttributes.ContentState.Trend` but is exposed here
    /// so callers do not need to import `ActivityKit` to invoke the
    /// coordinator.
    public enum Trend: String, Sendable {
        case up
        case down
        case flat
    }

    public static let shared = LiveActivityCoordinator()

    #if canImport(ActivityKit)
    private var activeActivity: Activity<MetricActivityAttributes>?
    #endif

    private init() {}

    /// Whether the system will allow us to start a Live Activity right now.
    public var isAvailable: Bool {
        #if canImport(ActivityKit)
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }

    /// Start (or update) a Live Activity for the given metric value. When an
    /// activity is already running for the same kind, the state is updated
    /// in place rather than requesting a new one.
    public func startAlert(
        kind: MetricKind,
        value: Double,
        trend: Trend = .up,
        timestamp: Date = Date()
    ) async {
        #if canImport(ActivityKit)
        guard isAvailable else { return }
        let activityTrend: MetricActivityAttributes.ContentState.Trend
        switch trend {
        case .up: activityTrend = .up
        case .down: activityTrend = .down
        case .flat: activityTrend = .flat
        }
        let attributes = MetricActivityAttributes(
            kindRaw: kind.rawValue,
            startedAt: timestamp,
            displayPreferenceRaw: MetricActivityAttributes.DisplayPreference.percentage.rawValue
        )
        let state = MetricActivityAttributes.ContentState.make(
            kindRaw: kind.rawValue,
            value: value,
            trend: activityTrend,
            timestamp: timestamp,
            isAvailable: true
        )
        let content = ActivityContent(state: state, staleDate: nil)

        if let active = activeActivity {
            await active.update(content)
        } else {
            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
                activeActivity = activity
            } catch {
                // Most common cause: user has Live Activities disabled for
                // kWatch. Silently swallow — the notification path is still
                // working, this is best-effort augmentation.
            }
        }
        #endif
    }

    /// End the active Live Activity, if any. Safe to call when none is
    /// running.
    public func endAlert() async {
        #if canImport(ActivityKit)
        guard let active = activeActivity else { return }
        await active.end(active.content, dismissalPolicy: .immediate)
        activeActivity = nil
        #endif
    }
}
