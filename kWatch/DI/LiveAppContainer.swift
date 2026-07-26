import Foundation
import MetricsKit

/// Production wiring. Constructs real adapters and aggregates them into a single container.
///
/// Note: `ProcessMonitor` is intentionally not included in the monitor list because
/// it does not conform to `MetricMonitor` — process data is queried on demand by
/// feature view-models (see Task 15).
public final class LiveAppContainer: AppContainerProtocol, @unchecked Sendable {
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
    public let coreDataStack: CoreDataStack
    public let storeManager: StoreManagerProtocol

    public init() {
        self.appState = AppState()
        self.purchaseState = PurchaseState()

        let defaults = UserDefaults(suiteName: "group.app.kraftly.shared") ?? .standard
        self.preferences = PreferencesRepository(defaults: defaults)
        self.metricsRepository = MetricsRepository(defaults: defaults)

        let stack: CoreDataStack
        do {
            stack = try CoreDataStack(
                inMemory: false,
                appGroupIdentifier: "group.app.kraftly.shared"
            )
        } catch {
            // Unsigned development builds may not have access to the App Group.
            stack = try! CoreDataStack(inMemory: true)
        }
        self.coreDataStack = stack
        self.historyRepository = HistoryRepository(stack: stack)
        self.alertRepository = AlertRepository(stack: stack)

        let directory: URL
        if let appGroupDirectory = AppGroupConfiguration.snapshotDirectory() {
            directory = appGroupDirectory
        } else {
            let fallback = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            directory = fallback.appendingPathComponent("kWatch", isDirectory: true)
        }
        self.snapshotWriter = SnapshotWriter(directory: directory)
        self.processMonitor = ProcessMonitor(provider: LibprocProcessProvider())
        self.notificationScheduler = NotificationScheduler()

        let monitors: [any MetricMonitor] = [
            CPUMonitor(provider: HostCPUStatsProvider()),
            MemoryMonitor(provider: HostMemoryStatsProvider()),
            DiskMonitor(path: "/", provider: StatfsDiskStatsProvider()),
            NetworkMonitor(provider: GetifaddrsNetworkStatsProvider()),
            TemperatureMonitor(provider: IOKitSMCReadingProvider()),
            FanMonitor(provider: IOKitSMCReadingProvider()),
            BatteryMonitor(provider: IOPSBatteryProvider())
        ]
        self.aggregator = MetricsAggregator(monitors: monitors, strategy: SamplingStrategy())
        self.storeManager = StoreManager(
            productID: "app.kraftly.kwatch.pro",
            purchaseState: purchaseState
        )
    }
}