import Foundation
import MetricsKit

/// Test stub for `IntentServiceProtocol`. Always returns canned data so intent
/// tests stay hermetic. Default values are designed to exercise both the
/// happy path and the Pro-gating path.
public final class StubIntentService: IntentServiceProtocol, @unchecked Sendable {
    public let snapshot: MetricSnapshot?
    public let proFlag: Bool
    public let startCalls: AtomicCounter
    public let stopCalls: AtomicCounter
    public let openCalls: AtomicCounter
    public let processes: [ProcessUsage]
    public let diagnosticsURL: URL?
    public let showTopProcessesCalls: AtomicCounter
    public let showDiskUsageCalls: AtomicCounter
    public let showNetworkRateCalls: AtomicCounter
    public private(set) var lastShowTopProcessesLimit: Int?
    public private(set) var lastShowDiskUsageVolume: DiskVolumeParameter?
    public private(set) var lastShowNetworkRateDirection: NetworkDirectionParameter?

    public init(
        snapshot: MetricSnapshot? = nil,
        isPro: Bool = false,
        processes: [ProcessUsage] = [],
        diagnosticsURL: URL? = nil
    ) {
        self.snapshot = snapshot
        self.proFlag = isPro
        self.startCalls = AtomicCounter()
        self.stopCalls = AtomicCounter()
        self.openCalls = AtomicCounter()
        self.processes = processes
        self.diagnosticsURL = diagnosticsURL
        self.showTopProcessesCalls = AtomicCounter()
        self.showDiskUsageCalls = AtomicCounter()
        self.showNetworkRateCalls = AtomicCounter()
    }

    public func latestSnapshot() async -> MetricSnapshot? { snapshot }
    public func startMonitoring() async { startCalls.increment() }
    public func stopMonitoring() async { stopCalls.increment() }
    public func openDashboard() async { openCalls.increment() }
    public func isPro() async -> Bool { proFlag }
    public func topProcesses(limit: Int) async throws -> [ProcessUsage] {
        Array(processes.prefix(limit))
    }
    public func formatMetric(kind: MetricKind) async -> String {
        guard let snapshot else { return IntentFormatter.unavailable(for: kind) }
        return IntentFormatter.format(kind: kind, snapshot: snapshot)
    }
    public func exportDiagnostics() async throws -> URL {
        guard let diagnosticsURL else {
            throw IntentServiceError.exportFailed("Diagnostics unavailable in stub.")
        }
        return diagnosticsURL
    }

    public func showTopProcesses(limit: Int) async {
        showTopProcessesCalls.increment()
        lastShowTopProcessesLimit = limit
    }

    public func showDiskUsage(volume: DiskVolumeParameter) async {
        showDiskUsageCalls.increment()
        lastShowDiskUsageVolume = volume
    }

    public func showNetworkRate(direction: NetworkDirectionParameter) async {
        showNetworkRateCalls.increment()
        lastShowNetworkRateDirection = direction
    }
}

/// Thread-safe counter for stub invocation assertions.
public final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int = 0

    public init() {}

    public func increment() {
        lock.lock(); defer { lock.unlock() }
        value += 1
    }

    public var current: Int {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}