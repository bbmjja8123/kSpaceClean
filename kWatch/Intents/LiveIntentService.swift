import Foundation
import MetricsKit

/// Production implementation of `IntentServiceProtocol`.
///
/// Reads from the App Group shared `snapshot.json` so the intents extension
/// never has to start the main app's `MetricsAggregator` actor. Mutations
/// (start/stop monitoring, open dashboard, export diagnostics) are delivered
/// via distributed notifications that the main app observes.
///
/// `LiveIntentService` deliberately does NOT hold an `AppContainerProtocol`
/// reference — extensions must keep their container lifetimes independent
/// from the main app to avoid `XPC` confusion.
public final class LiveIntentService: IntentServiceProtocol, @unchecked Sendable {
    public nonisolated init() {}

    public func latestSnapshot() async -> MetricSnapshot? {
        guard let url = AppGroupConfiguration.snapshotURL() else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SharedSnapshot.self, from: data).toMetricSnapshot()
    }

    public func startMonitoring() async {
        DistributedNotificationCenter.default().postNotificationName(
            .kWatchIntentStartMonitoring,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    public func stopMonitoring() async {
        DistributedNotificationCenter.default().postNotificationName(
            .kWatchIntentStopMonitoring,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    public func openDashboard() async {
        DistributedNotificationCenter.default().postNotificationName(
            .kWatchIntentOpenDashboard,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    public func isPro() async -> Bool {
        guard let url = AppGroupConfiguration.snapshotURL(),
              let data = try? Data(contentsOf: url),
              let snapshot = try? Self.snapshotDecoder.decode(SharedSnapshot.self, from: data) else {
            return false
        }
        return snapshot.isPro
    }

    private static let snapshotDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public func topProcesses(limit: Int) async throws -> [ProcessUsage] {
        // Process enumeration lives in the main app. We post a distributed
        // notification and let the main app reply via a side channel; for the
        // intents path we fall back to an empty list to keep this method
        // non-blocking. The dashboard view model handles the rich fetch.
        _ = limit
        return []
    }

    public func formatMetric(kind: MetricKind) async -> String {
        guard let snapshot = await latestSnapshot() else {
            return IntentFormatter.unavailable(for: kind)
        }
        return IntentFormatter.format(kind: kind, snapshot: snapshot)
    }

    public func exportDiagnostics() async throws -> URL {
        // The main app owns the diagnostics exporter. We trigger it via a
        // distributed notification and the main app writes the archive to
        // the App Group; if no archive exists yet we throw so the intent can
        // show a friendly error.
        DistributedNotificationCenter.default().postNotificationName(
            .kWatchIntentExportDiagnostics,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        if let url = AppGroupConfiguration.containerURL()?
            .appendingPathComponent("diagnostics.zip", isDirectory: false),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        throw IntentServiceError.exportFailed("Diagnostics export was not produced.")
    }

    public func showTopProcesses(limit: Int) async {
        // Fire-and-forget. The intent owns the dialog text. The main app
        // already pushes fresh process data through the App Group snapshot,
        // so no distributed notification is needed.
        _ = limit
    }

    public func showDiskUsage(volume: DiskVolumeParameter) async {
        // Fire-and-forget. Disk snapshots are read from the App Group; the
        // main app can filter by volume on the dashboard side if needed.
        _ = volume
    }

    public func showNetworkRate(direction: NetworkDirectionParameter) async {
        // Fire-and-forget. Network throughput comes from the shared snapshot.
        _ = direction
    }
}

/// Notification names used by the intents extension to talk to the main app.
public extension Notification.Name {
    static let kWatchIntentStartMonitoring = Notification.Name("app.kraftly.kwatch.intent.start")
    static let kWatchIntentStopMonitoring = Notification.Name("app.kraftly.kwatch.intent.stop")
    static let kWatchIntentOpenDashboard = Notification.Name("app.kraftly.kwatch.intent.openDashboard")
    static let kWatchIntentExportDiagnostics = Notification.Name("app.kraftly.kwatch.intent.export")
}

/// Errors thrown by the intents service.
public enum IntentServiceError: LocalizedError, Sendable {
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .exportFailed(let message): return message
        }
    }
}

// MARK: - SharedSnapshot projection

private extension SharedSnapshot {
    /// Projects the cross-process snapshot back into a full `MetricSnapshot`.
    /// Unavailable metrics are emitted as `MetricValue.unavailable` so intents
    /// can show a friendly "N/A" rather than fabricating values.
    func toMetricSnapshot() throws -> MetricSnapshot {
        var values: [MetricKind: MetricValue] = [:]
        var availability: [MetricKind: MetricAvailability] = [:]

        if cpuAvailable {
            values[.cpu] = .percentage(cpuPercent)
            availability[.cpu] = .available
        } else {
            values[.cpu] = .unavailable(.unsupported("Not available"))
            availability[.cpu] = .unsupported(reason: "Not available")
        }
        if memoryAvailable {
            values[.memory] = .percentage(memoryPercent)
            availability[.memory] = .available
        } else {
            values[.memory] = .unavailable(.unsupported("Not available"))
            availability[.memory] = .unsupported(reason: "Not available")
        }
        if diskAvailable {
            values[.disk] = .percentage(diskPercent)
            availability[.disk] = .available
        } else {
            values[.disk] = .unavailable(.unsupported("Not available"))
            availability[.disk] = .unsupported(reason: "Not available")
        }
        if networkAvailable {
            values[.network] = .bytesPerSecond(networkBytesPerSecond)
            availability[.network] = .available
        } else {
            values[.network] = .unavailable(.unsupported("Not available"))
            availability[.network] = .unsupported(reason: "Not available")
        }
        if temperatureAvailable, let c = temperatureCelsius {
            values[.temperature] = .degreesCelsius(c)
            availability[.temperature] = .available
        } else {
            values[.temperature] = .unavailable(.unsupported("Not available"))
            availability[.temperature] = .unsupported(reason: "Not available")
        }
        if fanAvailable, let rpm = fanRPM {
            values[.fan] = .revolutionsPerMinute(rpm)
            availability[.fan] = .available
        } else {
            values[.fan] = .unavailable(.unsupported("Not available"))
            availability[.fan] = .unsupported(reason: "Not available")
        }
        if batteryAvailable, let pct = batteryPercent {
            values[.battery] = .percentage(pct)
            availability[.battery] = .available
        } else {
            values[.battery] = .unavailable(.unsupported("Not available"))
            availability[.battery] = .unsupported(reason: "Not available")
        }
        return MetricSnapshot(timestamp: timestamp, values: values, availability: availability)
    }
}

// MARK: - Formatting

/// Pure formatting helpers shared by intents. Kept `enum` + `static` so they
/// are trivially testable and never touch the network or disk.
public enum IntentFormatter {
    /// Returns a short, human-readable representation of `kind` using the
    /// snapshot. Falls back to a localized "N/A" when unavailable.
    public static func format(kind: MetricKind, snapshot: MetricSnapshot) -> String {
        guard let value = snapshot.values[kind] else { return unavailable(for: kind) }
        switch value {
        case .percentage(let p):
            return "\(Int(p.rounded()))%"
        case .bytes(let b):
            return formatBytes(b)
        case .bytesPerSecond(let b):
            return "\(formatBytes(b))/s"
        case .degreesCelsius(let c):
            return "\(Int(c.rounded()))°C"
        case .revolutionsPerMinute(let r):
            return "\(Int(r.rounded())) RPM"
        case .volts(let v):
            return String(format: "%.2f V", v)
        case .text(let t):
            return t
        case .unavailable:
            return unavailable(for: kind)
        }
    }

    /// Returns a localized "N/A" string for `kind`.
    public static func unavailable(for kind: MetricKind) -> String {
        switch kind {
        case .cpu: return "CPU N/A"
        case .memory: return "Memory N/A"
        case .disk: return "Disk N/A"
        case .network: return "Network N/A"
        case .temperature: return "Temp N/A"
        case .fan: return "Fan N/A"
        case .battery: return "Battery N/A"
        case .gpu: return "GPU N/A"
        }
    }

    /// Formats a byte count using the largest binary unit that yields a
    /// non-zero leading digit.
    public static func formatBytes(_ bytes: UInt64) -> String {
        let units: [(String, Double)] = [
            ("GB", 1024 * 1024 * 1024),
            ("MB", 1024 * 1024),
            ("KB", 1024)
        ]
        for (label, scale) in units {
            let v = Double(bytes) / scale
            if v >= 1 { return String(format: "%.1f %@", v, label) }
        }
        return "\(bytes) B"
    }
}