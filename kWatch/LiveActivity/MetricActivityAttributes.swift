#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// The attributes and compact state shared by the kWatch Live Activity.
public struct MetricActivityAttributes: ActivityAttributes, Codable, Hashable, Sendable {
    /// The metric represented by the activity, encoded using `MetricKind.rawValue`.
    public let kindRaw: String
    /// The time at which monitoring for this activity began.
    public let startedAt: Date
    /// The user's display preference, such as `percentage`, `absolute`, or `compact`.
    public let displayPreferenceRaw: String

    /// The supported display preferences for an activity.
    public enum DisplayPreference: String, Codable, Hashable, Sendable {
        case percentage
        case absolute
        case compact
    }

    /// The dynamic value rendered by the Live Activity.
    public struct ContentState: Codable, Hashable, Sendable {
        /// The current percentage or numeric metric value.
        public let value: Double
        /// The direction of change since the previous update.
        public let trend: Trend
        /// The time at which this state was sampled.
        public let timestamp: Date
        /// Whether the metric is currently available on this Mac.
        public let isAvailable: Bool
        /// The unit displayed alongside `value`.
        public let displayUnit: String

        /// The direction of change used by the compact activity row.
        public enum Trend: String, Codable, Hashable, Sendable {
            case up
            case down
            case flat
        }

        /// Creates a content state for a metric kind without depending on MetricsKit values.
        public static func make(
            kindRaw: String,
            value: Double,
            trend: Trend = .flat,
            timestamp: Date = Date(),
            isAvailable: Bool = true
        ) -> Self {
            Self(
                value: value,
                trend: trend,
                timestamp: timestamp,
                isAvailable: isAvailable,
                displayUnit: unit(for: kindRaw)
            )
        }

        /// Creates a content state for a metric kind without depending on MetricsKit values.
        public static func make(
            kind: String,
            value: Double,
            trend: Trend = .flat,
            timestamp: Date = Date(),
            isAvailable: Bool = true
        ) -> Self {
            make(
                kindRaw: kind,
                value: value,
                trend: trend,
                timestamp: timestamp,
                isAvailable: isAvailable
            )
        }

        private static func unit(for kindRaw: String) -> String {
            switch kindRaw {
            case "temperature": return "°C"
            case "fan": return "RPM"
            case "network": return "B/s"
            case "cpu", "memory", "disk", "battery": return "%"
            default: return ""
            }
        }
    }

    /// Creates the fixed attributes for a metric activity.
    public init(
        kindRaw: String,
        startedAt: Date,
        displayPreferenceRaw: String
    ) {
        self.kindRaw = kindRaw
        self.startedAt = startedAt
        self.displayPreferenceRaw = displayPreferenceRaw
    }
}

extension MetricActivityAttributes {
    /// Uses the same epoch-based date representation as `SharedSnapshot`.
    public enum CodingKeys: String, CodingKey {
        case kindRaw
        case startedAt
        case displayPreferenceRaw
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kindRaw = try container.decode(String.self, forKey: .kindRaw)
        startedAt = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .startedAt))
        displayPreferenceRaw = try container.decode(String.self, forKey: .displayPreferenceRaw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kindRaw, forKey: .kindRaw)
        try container.encode(startedAt.timeIntervalSince1970, forKey: .startedAt)
        try container.encode(displayPreferenceRaw, forKey: .displayPreferenceRaw)
    }
}

extension MetricActivityAttributes.ContentState {
    /// Uses the same epoch-based date representation as `SharedSnapshot`.
    private enum CodingKeys: String, CodingKey {
        case value
        case trend
        case timestamp
        case isAvailable
        case displayUnit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(Double.self, forKey: .value)
        trend = try container.decode(Trend.self, forKey: .trend)
        timestamp = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .timestamp))
        isAvailable = try container.decode(Bool.self, forKey: .isAvailable)
        displayUnit = try container.decode(String.self, forKey: .displayUnit)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(trend, forKey: .trend)
        try container.encode(timestamp.timeIntervalSince1970, forKey: .timestamp)
        try container.encode(isAvailable, forKey: .isAvailable)
        try container.encode(displayUnit, forKey: .displayUnit)
    }
}
#endif
