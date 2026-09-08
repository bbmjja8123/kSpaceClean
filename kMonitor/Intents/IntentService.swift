import Foundation
import MetricsKit

/// Boundary between `AppIntent` types and the rest of the app.
///
/// Intents never touch `AppContainerProtocol` directly. They call into this
/// protocol so that:
/// - production builds wire `LiveIntentService` (which talks to a real
///   `AppContainerProtocol` constructed inside the intents extension),
/// - unit tests inject `StubIntentService` with canned data,
/// - intents never accidentally block the actor that owns the container.
///
/// All members are `async` so they can hop to a background actor and never
/// stall the AppIntents runtime when the container is busy.
@MainActor
public protocol IntentServiceProtocol: Sendable {
    /// Returns the freshest `MetricSnapshot` available in the App Group, or
    /// `nil` if no snapshot has been written yet.
    func latestSnapshot() async -> MetricSnapshot?

    /// Tells the app coordinator to start continuous metric monitoring.
    func startMonitoring() async

    /// Tells the app coordinator to stop continuous metric monitoring.
    func stopMonitoring() async

    /// Brings the main app to the foreground and navigates to the dashboard.
    /// Intents do not directly open SwiftUI windows (AppIntents does not run
    /// inside a SwiftUI scene); instead they send a distributed notification
    /// that the main app observes.
    func openDashboard() async

    /// Returns `true` when the user has an active Pro entitlement.
    func isPro() async -> Bool

    /// Returns the top processes sorted by CPU usage, capped at `limit`.
    /// Throws when the process monitor is unavailable or errors out.
    func topProcesses(limit: Int) async throws -> [ProcessUsage]

    /// Formats `kind` using the current snapshot. Returns a short
    /// human-readable string such as `"33%"` or `"1.2 GB/s"`.
    func formatMetric(kind: MetricKind) async -> String

    /// Triggers the diagnostics export flow. Returns the URL of the written
    /// archive, or throws if the export failed.
    func exportDiagnostics() async throws -> URL

    /// Fire-and-forget. Tells the app to surface the top processes dialog
    /// using `limit` entries. The intent itself owns the dialog text and
    /// formatting; the service only routes the side effect.
    func showTopProcesses(limit: Int) async

    /// Fire-and-forget. Tells the app to surface a disk usage dialog scoped
    /// to `volume` (system / data / external).
    func showDiskUsage(volume: DiskVolumeParameter) async

    /// Fire-and-forget. Tells the app to surface a network rate dialog
    /// filtered by `direction` (combined / download / upload).
    func showNetworkRate(direction: NetworkDirectionParameter) async
}

/// Lightweight process usage snapshot used by intents.
///
/// Defined here (rather than imported from `MetricsKit`) so the intents
/// extension does not depend on `ProcessMonitor`'s full provider stack.
public struct ProcessUsage: Codable, Equatable, Sendable {
    public let pid: Int32
    public let name: String
    public let cpuPercent: Double
    public let memoryMB: Double
    public let networkBytesPerSecond: UInt64?

    public init(pid: Int32, name: String, cpuPercent: Double, memoryMB: Double, networkBytesPerSecond: UInt64?) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryMB = memoryMB
        self.networkBytesPerSecond = networkBytesPerSecond
    }
}