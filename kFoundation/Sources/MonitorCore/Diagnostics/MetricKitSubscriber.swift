import Foundation

#if canImport(MetricKit)
import MetricKit
#endif

/// Subscribes to Apple `MetricKit` daily and crash payloads and persists
/// them to the App Group container. **Local-only** — no network calls,
/// uploads, or external services. Files land in
/// `<AppGroup>/Diagnostics/{metric,crash}-<isoTimestamp>.json` so they can
/// be bundled into the user-initiated diagnostics export or inspected by
/// the user through Finder.
///
/// `MetricKitSubscriber` is `@MainActor` because the AppKit-style
/// `MXMetricManager` / `MXCrashManager` callbacks are delivered on the
/// main thread and the underlying subscriber list is not thread-safe.
///
/// Note: Apple's `MetricKit` framework is not available on macOS, so the
/// MetricKit-specific entry points are compiled out on macOS. The type
/// still exists on macOS so the dependency graph (`AppContainerProtocol`,
/// `LiveAppContainer`, `TestAppContainer`) compiles unchanged; on macOS
/// `start()` / `stop()` are then no-ops and the `persist(...)` payload
/// helpers are unavailable.
@MainActor
public final class MetricKitSubscriber {
    /// Singleton used by `kWatchAppDelegate` to share a subscriber across
    /// the app lifetime. Tests should construct their own instance and
    /// invoke `start()` against it.
    public static let shared = MetricKitSubscriber()

    private let directoryProvider: @Sendable () -> URL?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var isStarted = false

    /// Default initializer used by `LiveAppContainer`. The directory
    /// provider returns the App Group `Diagnostics/` subdirectory.
    public init(directoryProvider: @escaping @Sendable () -> URL? = MetricKitSubscriber.defaultDirectory) {
        self.directoryProvider = directoryProvider
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Default App Group diagnostics directory. Returns nil when the App
    /// Group is not provisioned (unsigned dev builds).
    public static func defaultDirectory() -> URL? {
        guard let container = AppGroupConfiguration.containerURL() else { return nil }
        let directory = container.appendingPathComponent("Diagnostics", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Register with both `MXMetricManager` and `MXCrashManager`. Idempotent
    /// — repeated calls after the first `start()` are no-ops so the app
    /// delegate may safely call `start()` on every launch.
    public func start() {
        guard !isStarted else { return }
        isStarted = true
#if canImport(MetricKit) && (os(iOS) || os(tvOS) || os(watchOS))
        MXMetricManager.shared.add(self)
        MXCrashManager.shared.add(self)
#endif
    }

    /// Detach from the managers. Provided for completeness (mostly used by
    /// unit tests that tear down their subscriber between assertions).
    public func stop() {
        guard isStarted else { return }
        isStarted = false
#if canImport(MetricKit) && (os(iOS) || os(tvOS) || os(watchOS))
        MXMetricManager.shared.remove(self)
        MXCrashManager.shared.remove(self)
#endif
    }

    // MARK: - Persistence helpers

#if canImport(MetricKit) && (os(iOS) || os(tvOS) || os(watchOS))
    /// Persist a daily metric payload as JSON inside the App Group.
    /// Returns the URL written, or `nil` if the directory is unavailable
    /// or the payload is empty.
    @discardableResult
    public func persist(metricPayload: MXMetricPayload) -> URL? {
        guard let directory = directoryProvider() else { return nil }
        let url = nextURL(in: directory, prefix: "metric")
        let summary = MetricKitPayloadSummary(metricPayload: metricPayload, crashPayload: nil)
        do {
            let data = try encoder.encode(summary)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Persist a diagnostic payload (crashes / hangs / CPU exceptions).
    @discardableResult
    public func persist(diagnosticPayload: MXDiagnosticPayload) -> URL? {
        guard let directory = directoryProvider() else { return nil }
        let url = nextURL(in: directory, prefix: "crash")
        let summary = MetricKitPayloadSummary(metricPayload: nil, crashPayload: diagnosticPayload)
        do {
            let data = try encoder.encode(summary)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
#endif

    /// Returns a list of diagnostic files currently stored in the App
    /// Group, oldest first. Returns an empty array when the directory is
    /// missing.
    public func storedFiles() -> [URL] {
        guard let directory = directoryProvider(),
              let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        return contents.sorted { lhs, rhs in
            let lDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            let rDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            return lDate < rDate
        }
    }

    private func nextURL(in directory: URL, prefix: String) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return directory.appendingPathComponent("\(prefix)-\(stamp).json")
    }
}

#if canImport(MetricKit) && (os(iOS) || os(tvOS) || os(watchOS))
// MARK: - MXMetricManagerSubscriber

extension MetricKitSubscriber: MXMetricManagerSubscriber {
    nonisolated public func didReceive(_ payloads: [MXMetricPayload]) {
        Task { @MainActor in
            for payload in payloads {
                _ = self.persist(metricPayload: payload)
            }
        }
    }
}

// MARK: - MXDiagnosticPayloadSubscriber (full override)

extension MetricKitSubscriber: MXDiagnosticPayloadSubscriber {
    nonisolated public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        Task { @MainActor in
            for payload in payloads {
                _ = self.persist(diagnosticPayload: payload)
            }
        }
    }
}

// MARK: - Serializable summary

/// A redacted, Codable summary of a `MetricKit` payload. We never encode
/// the raw MetricKit objects (they contain paths and identifying
/// information); only aggregate signals that are safe to ship in a support
/// bundle.
private struct MetricKitPayloadSummary: Codable, Sendable {
    let kind: String
    let timestamp: Date
    let timeStampBegin: Date?
    let timeStampEnd: Date?
    let includesMultipleApplicationVersions: Bool
    let earliestAppVersion: String?
    let latestAppVersion: String?
    let cpuMetrics: CPUSummary?
    let memoryMetrics: MemorySummary?
    let diskIOMetrics: DiskIOSummary?
    let applicationLaunchMetrics: ApplicationLaunchSummary?
    let applicationResponsivenessMetrics: ApplicationResponsivenessSummary?
    let networkTransferMetrics: NetworkTransferSummary?
    let crashes: [CrashSummary]?
    let hangs: [HangSummary]?

    init(metricPayload: MXMetricPayload?, crashPayload: MXDiagnosticPayload?) {
        self.kind = metricPayload != nil ? "metric" : "crash"
        self.timestamp = Date()
        if let payload = metricPayload {
            self.timeStampBegin = payload.timeStampBegin
            self.timeStampEnd = payload.timeStampEnd
            self.includesMultipleApplicationVersions = payload.includesMultipleApplicationVersions
            self.earliestAppVersion = nil
            self.latestAppVersion = nil
            self.cpuMetrics = payload.cpuMetrics.map(CPUSummary.init(metrics:))
            self.memoryMetrics = payload.memoryMetrics.map(MemorySummary.init(metrics:))
            self.diskIOMetrics = nil
            self.applicationLaunchMetrics = payload.applicationLaunchMetrics.map(ApplicationLaunchSummary.init(metrics:))
            self.applicationResponsivenessMetrics = payload.applicationResponsivenessMetrics.map(ApplicationResponsivenessSummary.init(metrics:))
            self.networkTransferMetrics = payload.networkTransferMetrics.map(NetworkTransferSummary.init(metrics:))
            self.crashes = nil
            self.hangs = nil
        } else {
            self.timeStampBegin = nil
            self.timeStampEnd = nil
            self.includesMultipleApplicationVersions = false
            self.earliestAppVersion = nil
            self.latestAppVersion = nil
            self.cpuMetrics = nil
            self.memoryMetrics = nil
            self.diskIOMetrics = nil
            self.applicationLaunchMetrics = nil
            self.applicationResponsivenessMetrics = nil
            self.networkTransferMetrics = nil
            self.crashes = (crashPayload?.crashDiagnostics ?? []).map(CrashSummary.init)
            self.hangs = (crashPayload?.hangDiagnostics ?? []).map(HangSummary.init)
        }
    }
}

private struct CPUSummary: Codable, Sendable {
    let cumulativeCPUTime: String?

    init(metrics: MXCPUMetrics) {
        self.cumulativeCPUTime = String(describing: metrics.cumulativeCPUTime)
    }
}

private struct MemorySummary: Codable, Sendable {
    let peakMemoryUsage: String?
    let averageMemoryUsage: String?

    init(metrics: MXMemoryMetrics) {
        self.peakMemoryUsage = String(describing: metrics.peakMemoryUsage)
        self.averageMemoryUsage = String(describing: metrics.averageMemoryUsage)
    }
}

private struct DiskIOSummary: Codable, Sendable {
    let cumulativeLogicalWrites: String?
}

private struct ApplicationLaunchSummary: Codable, Sendable {
    let histogrammedTimeToFirstDraw: String?
    let histogrammedResumeTime: String?

    init(metrics: MXAppLaunchMetrics) {
        self.histogrammedTimeToFirstDraw = String(describing: metrics.histogrammedTimeToFirstDraw)
        self.histogrammedResumeTime = String(describing: metrics.histogrammedResumeTime)
    }
}

private struct ApplicationResponsivenessSummary: Codable, Sendable {
    let histogrammedScrollLatency: String?

    init(metrics: MXAppResponsivenessMetrics) {
        self.histogrammedScrollLatency = String(describing: metrics.histogrammedScrollLatency)
    }
}

private struct NetworkTransferSummary: Codable, Sendable {
    let cumulativeWifiUpload: String?
    let cumulativeWifiDownload: String?
    let cumulativeCellularUpload: String?
    let cumulativeCellularDownload: String?

    init(metrics: MXNetworkTransferMetrics) {
        self.cumulativeWifiUpload = String(describing: metrics.cumulativeWifiUpload)
        self.cumulativeWifiDownload = String(describing: metrics.cumulativeWifiDownload)
        self.cumulativeCellularUpload = String(describing: metrics.cumulativeCellularUpload)
        self.cumulativeCellularDownload = String(describing: metrics.cumulativeCellularDownload)
    }
}

private struct CrashSummary: Codable, Sendable {
    let crashReason: String?
    let terminationReason: String?
    let exceptionType: String?

    init(_ payload: MXCrashDiagnostic) {
        self.crashReason = payload.crashReason
        self.terminationReason = payload.terminationReason
        self.exceptionType = payload.exceptionType
    }
}

private struct HangSummary: Codable, Sendable {
    let hangDuration: String?

    init(_ payload: MXHangDiagnostic) {
        self.hangDuration = String(describing: payload.hangDuration)
    }
}
#endif
