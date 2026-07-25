import Foundation

/// A source of periodic readings for a single `MetricKind`.
///
/// A monitor performs exactly one job: produce a `MetricSample` when
/// asked. All concrete monitors (CPU, memory, disk, network, sensors)
/// are implemented in later tasks.
public protocol MetricMonitor: Sendable {
    /// The kind of metric this monitor produces.
    var kind: MetricKind { get }

    /// Take a single reading. The only entry point of a monitor.
    func sample() async throws -> MetricSample
}

/// How often live and history samples are taken.
public struct SamplingStrategy: Sendable, Equatable {
    /// Cadence for the live (foreground) sampling loop.
    public let interval: Duration
    /// Cadence for persisted history samples.
    public let historyInterval: Duration

    public init(interval: Duration = .seconds(2), historyInterval: Duration = .seconds(30)) {
        self.interval = interval
        self.historyInterval = historyInterval
    }
}
