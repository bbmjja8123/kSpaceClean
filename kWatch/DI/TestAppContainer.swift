import Foundation
import MetricsKit

/// Test wiring. Stubs must not touch disk, StoreKit, IOKit, or App Group containers.
@MainActor
public final class TestAppContainer: AppContainerProtocol, @unchecked Sendable {
    public let aggregator: MetricsAggregator
    public let appState: AppState
    public let purchaseState: PurchaseState
    public let preferences: PreferencesRepositoryProtocol
    public let metricsRepository: MetricsRepository
    public let historyRepository: HistoryRepositoryProtocol
    public let alertRepository: AlertRepositoryProtocol
    public let snapshotWriter: SnapshotWriterProtocol
    public let processMonitor: ProcessMonitor?
    public let notificationScheduler: NotificationSchedulerProtocol
    public let storeManager: StoreManagerProtocol
    public let diagnosticsExporter: any DiagnosticsExporting
    public let metricKitSubscriber: MetricKitSubscriber

    public init(
        cpu: MetricValue = .percentage(0),
        memory: MetricValue = .percentage(0),
        disk: MetricValue = .percentage(0),
        network: MetricValue = .bytesPerSecond(0),
        temperature: MetricValue = .unavailable(.unsupported("test")),
        fan: MetricValue = .unavailable(.unsupported("test")),
        battery: MetricValue = .percentage(0),
        gpu: MetricValue = .unavailable(.unsupported("test")),
        processMonitor: ProcessMonitor? = nil,
        notificationScheduler: NotificationSchedulerProtocol? = nil,
        storeManager: StoreManagerProtocol? = nil,
        diagnosticsExporter: (any DiagnosticsExporting)? = nil,
        metricKitSubscriber: MetricKitSubscriber? = nil
    ) {
        self.appState = AppState()
        self.purchaseState = PurchaseState()
        self.preferences = InMemoryPreferences()
        self.metricsRepository = MetricsRepository(
            defaults: UserDefaults(suiteName: "kWatch.tests.\(UUID().uuidString)") ?? .standard
        )
        self.historyRepository = InMemoryHistoryRepository()
        self.alertRepository = InMemoryAlertRepository()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kWatch.test.snapshot.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        self.snapshotWriter = SnapshotWriter(directory: directory)
        self.processMonitor = processMonitor
        self.notificationScheduler = notificationScheduler
            ?? NotificationScheduler(overriddenAuthStatus: .denied)
        let monitors: [any MetricMonitor] = [
            StubTestMonitor(kind: .cpu, value: cpu),
            StubTestMonitor(kind: .memory, value: memory),
            StubTestMonitor(kind: .disk, value: disk),
            StubTestMonitor(kind: .network, value: network),
            StubTestMonitor(kind: .temperature, value: temperature),
            StubTestMonitor(kind: .fan, value: fan),
            StubTestMonitor(kind: .battery, value: battery),
            StubTestMonitor(kind: .gpu, value: gpu)
        ]
        self.aggregator = MetricsAggregator(
            monitors: monitors,
            strategy: SamplingStrategy(interval: .milliseconds(1))
        )
        // Test wiring never touches StoreKit. We always fall back to a
        // `StubStoreManager` when callers do not pass an explicit
        // manager in. The stub does not open any I/O at construction
        // time and is safe to instantiate from any actor.
        if let provided = storeManager {
            self.storeManager = provided
        } else {
            self.storeManager = StubStoreManager(purchaseState: purchaseState)
        }
        self.diagnosticsExporter = diagnosticsExporter ?? StubDiagnosticsExporter()
        self.metricKitSubscriber = metricKitSubscriber ?? MetricKitSubscriber(
            directoryProvider: { nil }
        )
    }
}

private struct StubTestMonitor: MetricMonitor, Sendable {
    let kind: MetricKind
    let value: MetricValue

    func sample() async throws -> MetricSample {
        MetricSample(kind: kind, value: value, availability: .available, timestamp: Date())
    }
}

/// Test diagnostics exporter. Records every `export()` invocation into
/// `callCount` and returns a fixed URL supplied at construction time.
public final class StubDiagnosticsExporter: DiagnosticsExporting, @unchecked Sendable {
    public private(set) var callCount: Int = 0
    public private(set) var lastDestination: URL?

    public init() {}

    public func export() async throws -> URL {
        callCount += 1
        // Point at a guaranteed-existing temp URL; tests assert on
        // `callCount` rather than the file system when they need to
        // avoid touching disk.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kWatch.stub.diagnostics.\(UUID().uuidString).json")
        lastDestination = url
        return url
    }
}