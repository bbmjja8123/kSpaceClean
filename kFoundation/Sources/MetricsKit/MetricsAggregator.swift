import Foundation

/// Fan-out aggregator that periodically samples a collection of
/// `MetricMonitor`s and emits immutable `MetricSnapshot`s to any number
/// of consumers via an `AsyncStream`.
///
/// The actor owns the monitors and the sampling task. Multiple consumers
/// can subscribe concurrently — each receives its own stream and the
/// same snapshot is yielded to every subscriber. A failing monitor is
/// converted into an `.unavailable` value for that metric and does not
/// terminate the stream.
public actor MetricsAggregator {
    private let monitors: [any MetricMonitor]
    private let strategy: SamplingStrategy
    private let clock: any KWatchClock
    private var continuations: [UUID: AsyncStream<MetricSnapshot>.Continuation] = [:]
    private var task: Task<Void, Never>?

    public init(monitors: [any MetricMonitor],
                strategy: SamplingStrategy = .init(),
                clock: any KWatchClock = SystemClock()) {
        self.monitors = monitors
        self.strategy = strategy
        self.clock = clock
    }

    /// Create a new consumer stream. Each call yields its own stream
    /// backed by a private continuation; the underlying buffer policy
    /// drops stale frames so consumers always see the freshest sample.
    public func stream() -> AsyncStream<MetricSnapshot> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [id] _ in
                Task { [weak self] in
                    await self?.remove(id)
                }
            }
        }
    }

    /// Start the sampling loop. Idempotent — calling `start()` while a
    /// loop is already running is a no-op.
    public func start() {
        guard task == nil else { return }
        let interval = strategy.interval
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sampleOnce()
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Stop the sampling loop, finish all consumer streams, and clear
    /// the continuation registry. After `stop()` the aggregator can be
    /// restarted with `start()`.
    public func stop() {
        task?.cancel()
        task = nil
        continuations.values.forEach { $0.finish() }
        continuations.removeAll()
    }

    /// Sample every monitor concurrently, build a snapshot, and yield
    /// it to every active consumer.
    private func sampleOnce() async {
        let now = clock.now()
        var values: [MetricKind: MetricValue] = [:]
        var availability: [MetricKind: MetricAvailability] = [:]

        await withTaskGroup(of: MetricSample?.self) { group in
            for monitor in monitors {
                group.addTask {
                    do {
                        return try await monitor.sample()
                    } catch {
                        return MetricSample(
                            kind: monitor.kind,
                            value: .unavailable(MetricError.systemCall(String(describing: error), 0)),
                            availability: .unavailable(reason: String(describing: error)),
                            timestamp: now)
                    }
                }
            }
            for await sample in group {
                guard let sample else { continue }
                values[sample.kind] = sample.value
                availability[sample.kind] = sample.availability
            }
        }

        let snapshot = MetricSnapshot(timestamp: now, values: values, availability: availability)
        continuations.values.forEach { $0.yield(snapshot) }
    }

    private func remove(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}