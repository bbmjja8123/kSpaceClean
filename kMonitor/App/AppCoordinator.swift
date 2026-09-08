import Foundation
import MetricsKit
import Combine
#if canImport(WidgetKit)
import WidgetKit
import MonitorCore
#endif

/// Owns the long-lived sampling and persistence work for one app launch.
@MainActor
public final class AppCoordinator: ObservableObject {
    @Published public private(set) var isRunning = false

    private let container: any AppContainerProtocol
    private let clock: any KMonitorClock
    private var streamTask: Task<Void, Never>?
    private var lastHistoryAt: Date?

    public init(container: any AppContainerProtocol, clock: any KMonitorClock = SystemClock()) {
        self.container = container
        self.clock = clock
    }

    /// Starts sampling and consumes the aggregator stream. Repeated calls are ignored.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
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
        container.appState.setMonitoring(false)
        streamTask?.cancel()
        streamTask = nil

        let aggregator = container.aggregator
        Task { await aggregator.stop() }
    }

    private func process(
        snapshot: MetricSnapshot,
        container: any AppContainerProtocol,
        clock: any KMonitorClock
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
                    // Reload widget timelines for Pro users on macOS 14+ so
                    // Live Widgets reflect the alert-crossing value
                    // immediately instead of waiting for the next
                    // TimelineProvider tick.
                    if container.purchaseState.isPro {
                        notifyLiveWidgets(for: alert, value: value, at: now)
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

    /// Reload WidgetKit timelines when an alert fires so Live Widgets
    /// immediately reflect the post-alert metric value instead of waiting
    /// for the next TimelineProvider tick.
    private func notifyLiveWidgets(
        for alert: MetricAlert,
        value: MetricValue,
        at timestamp: Date
    ) {
        if #available(macOS 14.0, *) {
            // Only numeric metric kinds carry an alert-crossing value worth
            // an immediate reload; skip non-numeric payloads (.bytes, .volts,
            // .text, .unavailable) exactly as before.
            switch value {
            case .percentage, .degreesCelsius, .revolutionsPerMinute, .bytesPerSecond:
                break
            default: return
            }
            Task { @MainActor in
                // Refresh all configured widgets so the new metric value shows up
                // in the Notification Center / Desktop widget without waiting
                // for the next TimelineProvider tick. Available on macOS 13+; the
                // `#if canImport(WidgetKit)` guard keeps the type-checker happy
                // on any future SDK that might strip WidgetKit.
                #if canImport(WidgetKit)
                WidgetCenter.shared.reloadAllTimelines()
                #endif
            }
        }
    }
}
