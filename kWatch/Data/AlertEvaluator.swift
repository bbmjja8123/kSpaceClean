import Foundation
import MetricsKit

/// Stub evaluator. Task 16 may wrap this API with a clock-injecting evaluator.
public enum AlertEvaluator {
    public static func evaluate(
        snapshot: MetricSnapshot,
        alerts: [MetricAlert],
        now: Date = Date()
    ) -> [MetricAlert] {
        alerts.filter { alert in
            guard alert.isEnabled else { return false }
            if let lastTriggeredAt = alert.lastTriggeredAt,
               now.timeIntervalSince(lastTriggeredAt) < Double(alert.cooldownSeconds) {
                return false
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
