import Foundation

/// A filesystem capacity reading.
public struct DiskStats: Sendable, Equatable {
    public let totalBytes: UInt64
    public let freeBytes: UInt64

    public init(totalBytes: UInt64, freeBytes: UInt64) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
    }
}

/// Reads capacity statistics for a filesystem path.
public protocol DiskStatsProvider: Sendable {
    func read(path: String) throws -> DiskStats
}

/// Reports the percentage of capacity used by a filesystem.
public final class DiskMonitor: MetricMonitor, @unchecked Sendable {
    public let kind: MetricKind = .disk
    private let path: String
    private let provider: any DiskStatsProvider

    public init(path: String, provider: any DiskStatsProvider) {
        self.path = path
        self.provider = provider
    }

    public func sample() async throws -> MetricSample {
        let stats = try provider.read(path: path)
        let percent: Double
        if stats.totalBytes == 0 {
            percent = 0
        } else {
            let usedBytes = stats.totalBytes >= stats.freeBytes ? stats.totalBytes - stats.freeBytes : 0
            percent = Double(usedBytes) / Double(stats.totalBytes) * 100
        }
        return MetricSample(
            kind: .disk,
            value: .percentage(min(max(percent, 0), 100)),
            availability: .available,
            timestamp: Date()
        )
    }
}
