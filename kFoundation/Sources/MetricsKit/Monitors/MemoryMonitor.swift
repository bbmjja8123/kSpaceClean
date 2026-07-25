import Foundation

/// One snapshot of physical memory state in bytes.
public struct MemoryStats: Sendable, Equatable {
    public let totalBytes: UInt64
    public let activeBytes: UInt64

    public init(totalBytes: UInt64, activeBytes: UInt64) {
        self.totalBytes = totalBytes
        self.activeBytes = activeBytes
    }
}

/// A source of `MemoryStats` readings, typically wrapping
/// `host_statistics64` on Darwin platforms.
public protocol MemoryStatsProvider: Sendable {
    func read() throws -> MemoryStats
}

/// A `MetricMonitor` that reports the percentage of physical memory
/// currently in use (active + wired + compressed).
public final class MemoryMonitor: MetricMonitor, @unchecked Sendable {
    public let kind: MetricKind = .memory
    private let provider: any MemoryStatsProvider

    public init(provider: any MemoryStatsProvider) {
        self.provider = provider
    }

    public func sample() async throws -> MetricSample {
        let stats = try provider.read()
        let percent: Double
        if stats.totalBytes == 0 {
            percent = 0
        } else {
            percent = Double(stats.activeBytes) / Double(stats.totalBytes) * 100
        }
        let clamped = min(max(percent, 0), 100)
        return MetricSample(kind: .memory, value: .percentage(clamped), availability: .available, timestamp: Date())
    }
}