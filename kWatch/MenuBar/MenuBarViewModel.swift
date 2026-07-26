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
        if case .percentage(let v) = snapshot.values[.cpu] { cpuPercent = v }
        if case .percentage(let v) = snapshot.values[.memory] { memoryPercent = v }
        if case .percentage(let v) = snapshot.values[.disk] { diskPercent = v }
        if case .bytesPerSecond(let v) = snapshot.values[.network] { networkBytesPerSecond = v }
        cpuHistory.append(cpuPercent)
        if cpuHistory.count > historyCapacity {
            cpuHistory.removeFirst(cpuHistory.count - historyCapacity)
        }
        isPro = container.purchaseState.isPro
    }
}
