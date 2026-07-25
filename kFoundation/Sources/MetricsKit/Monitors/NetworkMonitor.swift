import Foundation

/// Aggregate receive and transmit byte counters for network interfaces.
public struct InterfaceBytes: Sendable, Equatable {
    public let receivedBytes: UInt64
    public let sentBytes: UInt64

    public init(receivedBytes: UInt64, sentBytes: UInt64) {
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
    }
}

/// Reads aggregate network interface counters.
public protocol NetworkStatsProvider: Sendable {
    func read() throws -> InterfaceBytes
}

/// Reports aggregate network throughput using consecutive counter deltas.
public final class NetworkMonitor: MetricMonitor, @unchecked Sendable {
    public let kind: MetricKind = .network
    private let provider: any NetworkStatsProvider
    private let clock: any KWatchClock
    private var previousBytes: InterfaceBytes?
    private var previousDate: Date?

    public init(provider: any NetworkStatsProvider, clock: any KWatchClock = SystemClock()) {
        self.provider = provider
        self.clock = clock
    }

    public func sample() async throws -> MetricSample {
        let current = try provider.read()
        let now = clock.now()
        defer {
            previousBytes = current
            previousDate = now
        }
        guard let previousBytes, let previousDate else {
            return MetricSample(kind: .network, value: .bytesPerSecond(0), availability: .available, timestamp: now)
        }
        let elapsed = now.timeIntervalSince(previousDate)
        guard elapsed > 0 else {
            return MetricSample(kind: .network, value: .bytesPerSecond(0), availability: .available, timestamp: now)
        }
        let receivedDelta = current.receivedBytes >= previousBytes.receivedBytes
            ? current.receivedBytes - previousBytes.receivedBytes
            : 0
        let sentDelta = current.sentBytes >= previousBytes.sentBytes
            ? current.sentBytes - previousBytes.sentBytes
            : 0
        let rate = UInt64(Double(receivedDelta + sentDelta) / elapsed)
        return MetricSample(kind: .network, value: .bytesPerSecond(rate), availability: .available, timestamp: now)
    }
}
