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

    public init() {
        self.appState = AppState()
        self.purchaseState = PurchaseState()
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
    }
}