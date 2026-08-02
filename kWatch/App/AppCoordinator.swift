import Foundation
import MetricsKit
import Combine

/// Owns the long-lived sampling and persistence work for one app launch.
@MainActor
public final class AppCoordinator: ObservableObject {
    @Published public private(set) var isRunning = false

    private let container: any AppContainerProtocol
    private let clock: any KWatchClock
    private var streamTask: Task<Void, Never>?
    private var lastHistoryAt: Date?
    private var isStopping = false

    public init(container: any AppContainerProtocol, clock: any KWatchClock = SystemClock()) {
        self.container = container
        self.clock = clock
    }

    /// Starts sampling and consumes the aggregator stream. Repeated calls are ignored.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        isStopping = false
        container.appState.setMonitoring(true)

        let container = self.container
        let clock = self.clock
        streamTask = Task { @MainActor [weak self] in
            await container.aggregator.start()
            let stream = await container.aggregator.stream()
            for await snapshot in stream {
                guard let self, self.isRunning, !Task.isCancelled else { break }
                self.process(snapshot: snapshot, container: container, clock: clock)
            }
        }
    }

    /// Stops sampling and cancels the stream consumer. Repeated calls are ignored.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        isStopping = true
        container.appState.setMonitoring(false)
        streamTask?.cancel()
        streamTask = nil

        let aggregator = container.aggregator
        Task { await aggregator.stop() }
    }

    private func process(
        snapshot: MetricSnapshot,
        container: any AppContainerProtocol,
        clock: any KWatchClock
    ) {
        let now = clock.now()
        container.metricsRepository.saveLatest(snapshot)
        container.appState.update(snapshot: snapshot)

        if lastHistoryAt == nil || now.timeIntervalSince(lastHistoryAt!) >= 60 {
            do {
                try container.historyRepository.append(snapshot)
                lastHistoryAt = now
            } catch {
                // History persistence is best-effort.
            }
        }

        do {
            let alerts = try container.alertRepository.all()
            let triggered = AlertEvaluator.evaluate(snapshot: snapshot, alerts: alerts, now: now)
            for alert in triggered {
                try? container.alertRepository.recordTriggered(id: alert.id, at: now)
                if let value = snapshot.values[alert.kind] {
                    let scheduler = container.notificationScheduler
                    Task.detached {
                        await scheduler.schedule(alert: alert, value: value)
                    }
                    // Start a Live Activity for Pro users on macOS 14+. The
                    // coordinator's `isAvailable` guard handles the user
                    // having disabled Live Activities for kWatch.
                    if container.purchaseState.isPro {
                        startLiveActivityIfPossible(for: alert, value: value, at: now)
                    }
                }
            }
        } catch {
            // Alert evaluation is best-effort.
        }

        let shared = SharedSnapshot(
            from: snapshot,
            isPro: container.purchaseState.isPro,
            menuBarMode: container.preferences.menuBarMode
        )
        try? container.snapshotWriter.write(shared)
    }

    /// Start a Live Activity for an alert fire, gated by macOS 14+ and the
    /// runtime authorization flag.
    private func startLiveActivityIfPossible(
        for alert: MetricAlert,
        value: MetricValue,
        at timestamp: Date
    ) {
        if #available(macOS 14.0, *) {
            let numeric: Double
            switch value {
            case let .percentage(v): numeric = v
            case let .degreesCelsius(v): numeric = v
            case let .revolutionsPerMinute(v): numeric = v
            case let .bytesPerSecond(v): numeric = Double(v)
            default: return
            }
            let trend: LiveActivityCoordinator.Trend =
                alert.op == .above ? .up : .down
            Task {
                await LiveActivityCoordinator.shared.startAlert(
                    kind: alert.kind,
                    value: numeric,
                    trend: trend,
                    timestamp: timestamp
                )
            }
        }
    }
}
