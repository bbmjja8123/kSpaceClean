// ActivityKit is iOS-only — in the Xcode 26 SDK (MacOSX26.2.sdk) the framework
// exists but is annotated `@available(macOS, unavailable)`, so on macOS every
// type in `ActivityKit` is rejected by the compiler. The kWatch project is a
// macOS-only app, so we gate this entire file (and its `ActivityAttributes`
// conformance) to iOS until Apple ships a macOS-native Live Activity API.
//
// When/if Apple introduces macOS Live Activity support, drop the `os(iOS)`
// gate and the type will compile again on macOS without further changes.
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// The attributes and compact state shared by the kWatch Live Activity.
///
/// Gated by `@available(macOS 14.0, *)` because `ActivityAttributes` is a macOS 14+ protocol.
/// The `ActivityAttributes` conformance is declared in a separate extension so the compiler
/// accepts the cross-availability conformance even on targets that don't yet know about
/// ActivityKit (this file is also compiled into the main kWatch app target at deployment
/// target 14.0, but the explicit split keeps the conformance gate clear and avoids future
/// availability-context surprises if a third target ever compiles this file).
@available(macOS 14.0, *)
public struct MetricActivityAttributes: Codable, Hashable, Sendable {
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
            case "temperature", "gpu": return "°C"
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

@available(macOS 14.0, *)
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

/// The `ActivityAttributes` conformance is gated explicitly by `@available(macOS 14.0, *)`
/// in its own extension so the compiler can resolve the cross-availability protocol lookup
/// independent of the struct declaration's context.
@available(macOS 14.0, *)
extension MetricActivityAttributes: ActivityAttributes {}

@available(macOS 14.0, *)
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
