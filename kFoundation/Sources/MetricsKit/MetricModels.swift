import Foundation

/// The category of a system metric that kWatch can observe.
public enum MetricKind: String, CaseIterable, Codable, Sendable {
    case cpu, memory, disk, network, temperature, fan, battery, gpu
}

extension MetricKind {
    /// Canonical display order for menu-bar presentation.
    public static var menuBarDisplayOrder: [MetricKind] {
        [.cpu, .memory, .disk, .network, .temperature, .fan, .battery, .gpu]
    }
}

/// A single, strongly-typed metric reading.
///
/// Cases carry only value-type payloads so that `MetricValue` is
/// trivially `Equatable`, `Codable`, and `Sendable` for persistence,
/// snapshots, and SwiftUI diffing.
public enum MetricValue: Codable, Equatable, Sendable {
    case percentage(Double)
    case bytes(UInt64)
    case bytesPerSecond(UInt64)
    case degreesCelsius(Double)
    case revolutionsPerMinute(Double)
    case volts(Double)
    case text(String)
    case unavailable(MetricError)

    /// The payload of `.percentage`, or `nil` for any other case.
    public var percentage: Double? {
        if case .percentage(let v) = self { return v }
        return nil
    }

    /// The payload of `.bytes`, or `nil` for any other case.
    public var bytes: UInt64? {
        if case .bytes(let v) = self { return v }
        return nil
    }

    /// The payload of `.bytesPerSecond`, or `nil` for any other case.
    public var bytesPerSecond: UInt64? {
        if case .bytesPerSecond(let v) = self { return v }
        return nil
    }

    /// The payload of `.degreesCelsius`, or `nil` for any other case.
    public var degreesCelsius: Double? {
        if case .degreesCelsius(let v) = self { return v }
        return nil
    }

    /// The payload of `.revolutionsPerMinute`, or `nil` for any other case.
    public var revolutionsPerMinute: Double? {
        if case .revolutionsPerMinute(let v) = self { return v }
        return nil
    }
}

/// Whether a metric can be produced on the current machine/OS.
public enum MetricAvailability: Codable, Equatable, Sendable {
    case available
    case unsupported(reason: String)
    case unavailable(reason: String)
}

/// One immutable reading emitted by a `MetricMonitor`.
public struct MetricSample: Codable, Equatable, Sendable {
    public let kind: MetricKind
    public let value: MetricValue
    public let availability: MetricAvailability
    public let timestamp: Date

    public init(kind: MetricKind, value: MetricValue, availability: MetricAvailability, timestamp: Date) {
        self.kind = kind
        self.value = value
        self.availability = availability
        self.timestamp = timestamp
    }
}

/// An immutable point-in-time collection of metric readings keyed by kind.
public struct MetricSnapshot: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let values: [MetricKind: MetricValue]
    public let availability: [MetricKind: MetricAvailability]

    public init(timestamp: Date, values: [MetricKind: MetricValue], availability: [MetricKind: MetricAvailability] = [:]) {
        self.timestamp = timestamp
        self.values = values
        self.availability = availability
    }
}

/// Errors raised while sampling a metric.
public enum MetricError: Error, Codable, Equatable, Sendable {
    case unsupported(String)
    case systemCall(String, Int32)
    case malformedData(String)
}
