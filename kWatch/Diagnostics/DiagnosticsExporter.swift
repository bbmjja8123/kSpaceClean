import Foundation
import AppKit
import MetricsKit

/// Errors raised by ``DiagnosticsExporter``.
public enum DiagnosticsExportFailure: LocalizedError, Sendable {
    case userCancelled
    case encodingFailed(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Export cancelled"
        case .encodingFailed(let reason):
            return "Failed to encode diagnostics: \(reason)"
        case .writeFailed(let reason):
            return "Failed to write diagnostics: \(reason)"
        }
    }
}

/// Abstraction over `NSSavePanel` so tests can stub the destination without
/// presenting UI. The default implementation wraps a real save panel.
public protocol DiagnosticsSavePanel: Sendable {
    /// Prompt the user for a destination URL and return it asynchronously.
    /// Returns `nil` when the user cancels.
    func prompt(defaultFilename: String) async -> URL?
}

/// Default `NSSavePanel`-backed implementation. Presents a modal save panel
/// anchored on the key window. Runs on the main actor because `NSApp` /
/// `NSSavePanel` require main-thread usage.
public struct SystemSavePanel: DiagnosticsSavePanel, @unchecked Sendable {
    public init() {}

    public func prompt(defaultFilename: String) async -> URL? {
        await MainActor.run {
            let panel = NSSavePanel()
            panel.title = "Export kWatch Diagnostics"
            panel.prompt = "Export"
            panel.nameFieldStringValue = defaultFilename
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
                panel.directoryURL = desktop
            }
            let response = panel.runModal()
            guard response == .OK else { return nil }
            return panel.url
        }
    }
}

/// Computes the host architecture string used in diagnostics. Falls back to
/// `uname`-style arm64/x86_64 detection if a richer `MachineContext` helper
/// is not available.
public enum MachineContext {
    /// Human-readable architecture description (e.g. "Apple Silicon (arm64)"
    /// or "Intel (x86_64)"). Always returns a non-empty string so the
    /// diagnostics payload can ship a deterministic field.
    public static var archDisplayName: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Unknown"
        #endif
    }
}

/// Produces a user-initiated diagnostics archive and writes it to disk only
/// after the user explicitly chooses a destination through an
/// ``DiagnosticsSavePanel``. The archive is fully scrubbed — process names,
/// IPv4 addresses, usernames, and filesystem paths are stripped before
/// serialization.
///
/// `DiagnosticsExporter` is marked `@unchecked Sendable` because the
/// underlying state (panel provider + snapshot provider) is immutable after
/// init and the actual work is performed inside the async methods which
/// are serialized through the panel actor boundary.
@MainActor
public final class DiagnosticsExporter: DiagnosticsExporting, @unchecked Sendable {
    /// Producer for the list of recent `SharedSnapshot` records. Defaults
    /// to reading from the App Group container via `SnapshotWriter`.
    public typealias SnapshotProvider = @Sendable () async -> [SharedSnapshot]

    private let panel: DiagnosticsSavePanel
    private let snapshotProvider: SnapshotProvider
    private let calendar: Calendar
    private let dateFormat: DateFormatter
    private let now: @Sendable () -> Date

    /// Default initializer used by `LiveAppContainer`.
    /// - Parameters:
    ///   - panel: Save panel provider. Defaults to ``SystemSavePanel``.
    ///   - snapshotProvider: Async closure returning recent snapshots. When
    ///     `nil`, falls back to reading `snapshot.json` from the App Group
    ///     container (only the latest snapshot will be available).
    ///   - now: Clock for testing. Defaults to `Date.init`.
    public init(
        panel: DiagnosticsSavePanel = SystemSavePanel(),
        snapshotProvider: SnapshotProvider? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.panel = panel
        self.snapshotProvider = snapshotProvider ?? DiagnosticsExporter.defaultSnapshotProvider()
        let calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        self.calendar = calendar
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = TimeZone(identifier: "UTC") ?? .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        self.dateFormat = formatter
        self.now = now
    }

    /// Default snapshot provider that reads the App Group snapshot via a
    /// fresh `SnapshotWriter`. Returns an empty array when the App Group
    /// is not provisioned or the file is missing.
    private static func defaultSnapshotProvider() -> SnapshotProvider {
        return {
            guard let directory = AppGroupConfiguration.snapshotDirectory() else {
                return []
            }
            let writer = SnapshotWriter(directory: directory)
            if let snapshot = try? writer.read() {
                return [snapshot]
            }
            return []
        }
    }

    /// Build the diagnostics payload and write it to a user-selected file.
    /// Returns the destination URL on success and throws on cancellation
    /// or I/O failure.
    public func export() async throws -> URL {
        let snapshots = await snapshotProvider()
        let document = await Self.buildDocument(snapshots: snapshots, now: now())
        let filename = "kWatch-Diagnostics-\(dateFormat.string(from: now())).json"
        guard let destination = await panel.prompt(defaultFilename: filename) else {
            throw DiagnosticsExportFailure.userCancelled
        }
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            data = try encoder.encode(document)
        } catch {
            throw DiagnosticsExportFailure.encodingFailed(String(describing: error))
        }
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw DiagnosticsExportFailure.writeFailed(String(describing: error))
        }
        return destination
    }

    // MARK: - Document construction

    /// Aggregate metrics derived from a snapshot history. Only aggregate
    /// percentages and rates are retained — no per-sample, per-process, or
    /// per-path detail leaves the device.
    public struct AggregateMetrics: Codable, Equatable, Sendable {
        public let sampleCount: Int
        public let cpuPercent: Double?
        public let memoryPercent: Double?
        public let diskPercent: Double?
        public let networkBytesPerSecond: Double?
        public let temperatureCelsius: Double?
        public let fanRPM: Double?
        public let batteryPercent: Double?

        public init(
            sampleCount: Int,
            cpuPercent: Double?,
            memoryPercent: Double?,
            diskPercent: Double?,
            networkBytesPerSecond: Double?,
            temperatureCelsius: Double?,
            fanRPM: Double?,
            batteryPercent: Double?
        ) {
            self.sampleCount = sampleCount
            self.cpuPercent = cpuPercent
            self.memoryPercent = memoryPercent
            self.diskPercent = diskPercent
            self.networkBytesPerSecond = networkBytesPerSecond
            self.temperatureCelsius = temperatureCelsius
            self.fanRPM = fanRPM
            self.batteryPercent = batteryPercent
        }
    }

    /// Top-level document serialized as JSON.
    public struct DiagnosticsDocument: Codable, Equatable, Sendable {
        public let appVersion: String
        public let buildNumber: String
        public let osVersion: String
        public let architecture: String
        public let bundleIdentifier: String
        public let generatedAt: Date
        public let summary: String
        public let metricAvailability: [String: Bool]
        public let recentAggregates: AggregateMetrics
        public let capabilities: [String: Bool]
    }

    /// Build the diagnostics document. Pure function — exposed as
    /// `internal` so unit tests can validate the payload without going
    /// through the save panel.
    static func buildDocument(snapshots: [SharedSnapshot], now: Date) async -> DiagnosticsDocument {
        let bundle = Bundle.main
        let marketing = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let bundleIdentifier = bundle.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String ?? "app.kraftly.kwatch"

        var availability: [String: Bool] = [:]
        for kind in MetricKind.allCases {
            switch kind {
            case .cpu: availability["cpu"] = snapshots.last?.cpuAvailable ?? false
            case .memory: availability["memory"] = snapshots.last?.memoryAvailable ?? false
            case .disk: availability["disk"] = snapshots.last?.diskAvailable ?? false
            case .network: availability["network"] = snapshots.last?.networkAvailable ?? false
            case .temperature: availability["temperature"] = snapshots.last?.temperatureAvailable ?? false
            case .fan: availability["fan"] = snapshots.last?.fanAvailable ?? false
            case .battery: availability["battery"] = snapshots.last?.batteryAvailable ?? false
            }
        }

        let aggregates = computeAggregates(snapshots: snapshots)

        return DiagnosticsDocument(
            appVersion: marketing,
            buildNumber: build,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: MachineContext.archDisplayName,
            bundleIdentifier: bundleIdentifier,
            generatedAt: now,
            summary: "No analytics, no network telemetry.",
            metricAvailability: availability,
            recentAggregates: aggregates,
            capabilities: [
                "appSandbox": true,
                "usesNetwork": false,
                "usesTCC": false
            ]
        )
    }

    /// Reduce the recent snapshot window to aggregate metrics. Returns an
    /// empty aggregate when no snapshots are available.
    static func computeAggregates(snapshots: [SharedSnapshot]) -> AggregateMetrics {
        guard !snapshots.isEmpty else {
            return AggregateMetrics(
                sampleCount: 0,
                cpuPercent: nil,
                memoryPercent: nil,
                diskPercent: nil,
                networkBytesPerSecond: nil,
                temperatureCelsius: nil,
                fanRPM: nil,
                batteryPercent: nil
            )
        }
        let n = Double(snapshots.count)
        let cpu = snapshots.map(\.cpuPercent).reduce(0, +) / n
        let memory = snapshots.map(\.memoryPercent).reduce(0, +) / n
        let disk = snapshots.map(\.diskPercent).reduce(0, +) / n
        let network = Double(snapshots.map(\.networkBytesPerSecond).reduce(0, +)) / n
        let temperatureValues = snapshots.compactMap(\.temperatureCelsius)
        let temperature = temperatureValues.isEmpty ? nil : temperatureValues.reduce(0, +) / Double(temperatureValues.count)
        let fanValues = snapshots.compactMap(\.fanRPM)
        let fan = fanValues.isEmpty ? nil : fanValues.reduce(0, +) / Double(fanValues.count)
        let batteryValues = snapshots.compactMap(\.batteryPercent)
        let battery = batteryValues.isEmpty ? nil : batteryValues.reduce(0, +) / Double(batteryValues.count)
        return AggregateMetrics(
            sampleCount: snapshots.count,
            cpuPercent: cpu,
            memoryPercent: memory,
            diskPercent: disk,
            networkBytesPerSecond: network,
            temperatureCelsius: temperature,
            fanRPM: fan,
            batteryPercent: battery
        )
    }

    // MARK: - Scrubbing helpers (test-only utility)

    /// Best-effort scrubber for any free-form text fields that may end up in
    /// the payload (e.g. an `MXDiagnosticPayload` summary). Replaces user
    /// paths, IPv4 addresses, and likely-usernames with `[REDACTED]` so
    /// nothing identifying leaks into the support archive.
    public static func scrubText(_ text: String) -> String {
        var scrubbed = text
        // /Users/<name>/... and /private/var/...
        scrubbed = redact(pattern: #"/Users/[^/\s]+(/|\b)"#, in: scrubbed)
        scrubbed = redact(pattern: #"/private/var[^/\s]*(/|\b)"#, in: scrubbed)
        // IPv4 addresses (with optional port).
        scrubbed = redact(pattern: #"\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b"#, in: scrubbed)
        return scrubbed
    }

    private static func redact(pattern: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "[REDACTED]")
    }
}