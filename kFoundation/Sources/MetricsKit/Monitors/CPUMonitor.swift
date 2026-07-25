import Foundation

/// One snapshot of cumulative CPU tick counts across all cores.
public struct CPUStats: Sendable, Equatable {
    public let user: UInt64
    public let system: UInt64
    public let idle: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
    }
}

/// A source of `CPUStats` readings, typically wrapping
/// `host_processor_info` on Darwin platforms.
public protocol CPUStatsProvider: Sendable {
    func read() throws -> CPUStats
}

/// A `MetricMonitor` that reports aggregate CPU usage as a percentage
/// derived from the delta between two consecutive `CPUStats` readings.
///
/// The first sample returns 0% because there is no previous reference
/// to diff against — callers should discard it.
public final class CPUMonitor: MetricMonitor, @unchecked Sendable {
    public let kind: MetricKind = .cpu
    private let provider: any CPUStatsProvider
    private var previous: CPUStats?

    public init(provider: any CPUStatsProvider) {
        self.provider = provider
    }

    public func sample() async throws -> MetricSample {
        let current = try provider.read()
        defer { previous = current }
        guard let previous else {
            return MetricSample(kind: .cpu, value: .percentage(0), availability: .available, timestamp: Date())
        }
        let totalDelta = (current.user + current.system + current.idle) - (previous.user + previous.system + previous.idle)
        let idleDelta = current.idle - previous.idle
        let usage: Double
        if totalDelta == 0 {
            usage = 0
        } else {
            usage = Double(totalDelta - idleDelta) / Double(totalDelta) * 100
        }
        let clamped = min(max(usage, 0), 100)
        return MetricSample(kind: .cpu, value: .percentage(clamped), availability: .available, timestamp: Date())
    }
}