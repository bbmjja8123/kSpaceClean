import Foundation
import MetricsKit

/// Pure evaluation of threshold alerts against a metric snapshot.
///
/// Task 16 may wrap this API with a clock-injecting evaluator.
public enum AlertEvaluator {
    /// Hard floor on alert frequency, in seconds: at most one alert per
    /// metric every 5 minutes, regardless of the configured cooldown.
    public static let minimumCooldownSeconds = 300

    /// Returns true if an alert for the given kind may fire now.
    /// Cooldown floor: at most one alert per metric every 5 minutes.
    public static func shouldFire(
        kind: MetricKind,
        lastFireTime: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let lastFireTime else { return true }
        return now.timeIntervalSince(lastFireTime) >= 300
    }

    public static func evaluate(
        snapshot: MetricSnapshot,
        alerts: [MetricAlert],
        now: Date = Date()
    ) -> [MetricAlert] {
        alerts.filter { alert in
            guard alert.isEnabled else { return false }
            if let lastTriggeredAt = alert.lastTriggeredAt {
                // The 5-minute floor always applies; a user-configured cooldown
                // LONGER than the floor still takes precedence.
                let floorMet = AlertEvaluator.shouldFire(
                    kind: alert.kind,
                    lastFireTime: lastTriggeredAt,
                    now: now
                )
                let perAlertMet =
                    now.timeIntervalSince(lastTriggeredAt) >= Double(alert.cooldownSeconds)
                if !floorMet || !perAlertMet {
                    return false
                }
            }
            guard let value = snapshot.values[alert.kind] else { return false }
            return matches(value: value, alert: alert)
        }
    }

    private static func matches(value: MetricValue, alert: MetricAlert) -> Bool {
        let number: Double?
        switch value {
        case let .percentage(value):
            number = value
        case let .degreesCelsius(value):
            number = value
        case let .revolutionsPerMinute(value):
            number = value
        case let .bytesPerSecond(value):
            number = Double(value)
        default:
            number = nil
        }
        guard let number else { return false }
        switch alert.op {
        case .above:
            return number > alert.threshold
        case .below:
            return number < alert.threshold
        }
    }
}
