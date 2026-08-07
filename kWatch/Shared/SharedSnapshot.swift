import Foundation
import MetricsKit

/// Cross-process-readable subset of a `MetricSnapshot`.
///
/// The Widget, Live Activity, and Intents extensions use this type. It never contains
/// process names, user paths, or identifying information — only aggregate metrics.
public struct SharedSnapshot: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let cpuPercent: Double
    public let memoryPercent: Double
    public let diskPercent: Double
    public let networkBytesPerSecond: UInt64
    public let temperatureCelsius: Double?
    public let fanRPM: Double?
    public let batteryPercent: Double?
    public let gpuTemperature: Double?
    public let cpuAvailable: Bool
    public let memoryAvailable: Bool
    public let diskAvailable: Bool
    public let networkAvailable: Bool
    public let temperatureAvailable: Bool
    public let fanAvailable: Bool
    public let batteryAvailable: Bool
    public let gpuAvailable: Bool
    public let isPro: Bool
    public let menuBarModeRaw: String

    public init(
        timestamp: Date,
        cpuPercent: Double,
        memoryPercent: Double,
        diskPercent: Double,
        networkBytesPerSecond: UInt64,
        temperatureCelsius: Double?,
        fanRPM: Double?,
        batteryPercent: Double?,
        gpuTemperature: Double? = nil,
        cpuAvailable: Bool,
        memoryAvailable: Bool,
        diskAvailable: Bool,
        networkAvailable: Bool,
        temperatureAvailable: Bool,
        fanAvailable: Bool,
        batteryAvailable: Bool,
        gpuAvailable: Bool = false,
        isPro: Bool,
        menuBarModeRaw: String
    ) {
        self.timestamp = timestamp
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.diskPercent = diskPercent
        self.networkBytesPerSecond = networkBytesPerSecond
        self.temperatureCelsius = temperatureCelsius
        self.fanRPM = fanRPM
        self.batteryPercent = batteryPercent
        self.gpuTemperature = gpuTemperature
        self.cpuAvailable = cpuAvailable
        self.memoryAvailable = memoryAvailable
        self.diskAvailable = diskAvailable
        self.networkAvailable = networkAvailable
        self.temperatureAvailable = temperatureAvailable
        self.fanAvailable = fanAvailable
        self.batteryAvailable = batteryAvailable
        self.gpuAvailable = gpuAvailable
        self.isPro = isPro
        self.menuBarModeRaw = menuBarModeRaw
    }

    /// Convenience initializer that projects a `MetricSnapshot` plus availability + UI state.
    public init(from snapshot: MetricSnapshot, isPro: Bool, menuBarMode: MenuBarMode) {
        self.timestamp = snapshot.timestamp
        self.cpuPercent = SharedSnapshot.value(of: snapshot.values[.cpu]) ?? 0
        self.memoryPercent = SharedSnapshot.value(of: snapshot.values[.memory]) ?? 0
        self.diskPercent = SharedSnapshot.value(of: snapshot.values[.disk]) ?? 0
        if case .bytesPerSecond(let b) = snapshot.values[.network] {
            self.networkBytesPerSecond = b
        } else {
            self.networkBytesPerSecond = 0
        }
        self.temperatureCelsius = SharedSnapshot.value(of: snapshot.values[.temperature])
        self.fanRPM = SharedSnapshot.value(of: snapshot.values[.fan])
        self.batteryPercent = SharedSnapshot.value(of: snapshot.values[.battery])
        self.gpuTemperature = SharedSnapshot.value(of: snapshot.values[.gpu])
        self.cpuAvailable = SharedSnapshot.isAvailable(snapshot.availability[.cpu])
        self.memoryAvailable = SharedSnapshot.isAvailable(snapshot.availability[.memory])
        self.diskAvailable = SharedSnapshot.isAvailable(snapshot.availability[.disk])
        self.networkAvailable = SharedSnapshot.isAvailable(snapshot.availability[.network])
        self.temperatureAvailable = SharedSnapshot.isAvailable(snapshot.availability[.temperature])
        self.fanAvailable = SharedSnapshot.isAvailable(snapshot.availability[.fan])
        self.batteryAvailable = SharedSnapshot.isAvailable(snapshot.availability[.battery])
        self.gpuAvailable = SharedSnapshot.isAvailable(snapshot.availability[.gpu])
        self.isPro = isPro
        self.menuBarModeRaw = menuBarMode.rawValue
    }

    private static func value(of metric: MetricValue?) -> Double? {
        guard let metric else { return nil }
        switch metric {
        case .percentage(let d): return d
        case .bytesPerSecond(let b): return Double(b)
        case .degreesCelsius(let d): return d
        case .revolutionsPerMinute(let d): return d
        case .bytes(let b): return Double(b)
        case .volts(let v): return v
        case .text, .unavailable: return nil
        }
    }

    private static func isAvailable(_ availability: MetricAvailability?) -> Bool {
        if case .available = availability { return true }
        return false
    }

    /// Staleness threshold. Widgets/extensions show "stale" UI when the snapshot
    /// is older than this.
    public static let stalenessThreshold: TimeInterval = 30

    public var isStale: Bool {
        Date().timeIntervalSince(timestamp) > Self.stalenessThreshold
    }
}
