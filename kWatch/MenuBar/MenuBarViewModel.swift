import Foundation
import Combine
import MetricsKit

/// Drives the menu-bar surface: consumes the shared `MetricsAggregator`
/// stream, exposes formatted display values, and persists the current
/// `MenuBarMode` selection.
///
/// The view model is `@MainActor` and `ObservableObject` so SwiftUI can
/// observe published values directly. It owns a single stream task that is
/// started on `start()` and torn down on `stop()`; it performs no monitoring
/// side effects beyond reading the aggregator's fan-out stream.
@MainActor
public final class MenuBarViewModel: ObservableObject {
    @Published public private(set) var cpuPercent: Double = 0
    @Published public private(set) var memoryPercent: Double = 0
    @Published public private(set) var diskPercent: Double = 0
    @Published public private(set) var networkBytesPerSecond: UInt64 = 0
    @Published public private(set) var networkBytesSent: UInt64 = 0
    @Published public private(set) var networkBytesReceived: UInt64 = 0
    @Published public private(set) var temperatureCelsius: Double? = nil
    @Published public private(set) var fanRPM: Int? = nil
    @Published public private(set) var batteryPercent: Double? = nil
    @Published public private(set) var cpuHistory: [Double] = []
    @Published public var mode: MenuBarMode = .trend {
        didSet {
            if mode != oldValue { preferences.menuBarMode = mode }
        }
    }
    @Published public private(set) var isPro: Bool = false

    private let container: any AppContainerProtocol
    private var preferences: any PreferencesRepositoryProtocol
    private let historyCapacity: Int
    private var streamTask: Task<Void, Never>?

    public init(container: any AppContainerProtocol, historyCapacity: Int = 30) {
        self.container = container
        self.preferences = container.preferences
        self.historyCapacity = historyCapacity
        self.mode = preferences.menuBarMode
        self.isPro = container.purchaseState.isPro
    }

    /// Begin consuming the aggregator's snapshot stream. Idempotent — a
    /// second call while a stream task is already running is a no-op.
    public func start() {
        guard streamTask == nil else { return }
        let aggregator = container.aggregator
        streamTask = Task { @MainActor [weak self] in
            let stream = await aggregator.stream()
            for await snapshot in stream {
                guard let self else { break }
                self.consume(snapshot: snapshot)
            }
        }
    }

    /// Cancel the stream task. Safe to call multiple times.
    public func stop() {
        streamTask?.cancel()
        streamTask = nil
    }

    /// Update the current display mode (also persisted via the `mode` setter).
    public func setMode(_ mode: MenuBarMode) {
        self.mode = mode
    }

    /// The compact status-item title for the current mode.
    ///
    /// - `.trend` renders a chart in the popover, so the title stays empty.
    /// - `.numeric` shows CPU and memory percentages.
    /// - `.minimal` shows only CPU percentage.
    public var title: String {
        switch mode {
        case .trend: return ""
        case .numeric: return "CPU \(Int(cpuPercent))%  MEM \(Int(memoryPercent))%"
        case .minimal: return "\(Int(cpuPercent))%"
        }
    }

    private func consume(snapshot: MetricSnapshot) {
        cpuPercent = snapshot.values[.cpu]?.percentage ?? 0
        memoryPercent = snapshot.values[.memory]?.percentage ?? 0
        diskPercent = snapshot.values[.disk]?.percentage ?? 0

        // `MetricValue.bytesPerSecond` carries a single combined total; the
        // send/receive split is not yet available at the monitor level.
        if case let .bytesPerSecond(total) = snapshot.values[.network] {
            networkBytesSent = 0
            networkBytesReceived = total
            networkBytesPerSecond = total
            // TODO: split via /proc/net/dev
        } else {
            networkBytesSent = 0
            networkBytesReceived = 0
            networkBytesPerSecond = 0
        }

        // Pro-only metrics: cleared for free users (the UI renders a lock).
        let pro = container.purchaseState.isPro
        temperatureCelsius = pro ? snapshot.values[.temperature]?.degreesCelsius : nil
        fanRPM = pro ? snapshot.values[.fan]?.revolutionsPerMinute.map(Int.init) : nil
        batteryPercent = pro ? snapshot.values[.battery]?.percentage : nil

        // Append to history, normalized to 0...1 (MiniTrendChart auto-scales).
        cpuHistory.append(cpuPercent / 100)
        if cpuHistory.count > historyCapacity {
            cpuHistory.removeFirst(cpuHistory.count - historyCapacity)
        }
        isPro = pro
    }
}
