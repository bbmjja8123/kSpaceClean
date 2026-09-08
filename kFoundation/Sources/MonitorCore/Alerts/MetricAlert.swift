import Foundation
import MetricsKit

public struct MetricAlert: Codable, Sendable, Equatable, Identifiable {
    /// Persisted comparison direction. This is intentionally separate from the
    /// generic UI-facing `AlertOperator` preferences type.
    public enum Operator: String, Codable, Sendable {
        case above
        case below
    }

    public let id: UUID
    public let kind: MetricKind
    public let op: Operator
    public let threshold: Double
    public let isEnabled: Bool
    public let cooldownSeconds: Int
    public let lastTriggeredAt: Date?

    public init(
        id: UUID = UUID(),
        kind: MetricKind,
        op: Operator,
        threshold: Double,
        isEnabled: Bool = true,
        cooldownSeconds: Int = 60,
        lastTriggeredAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.op = op
        self.threshold = threshold
        self.isEnabled = isEnabled
        self.cooldownSeconds = cooldownSeconds
        self.lastTriggeredAt = lastTriggeredAt
    }
}
