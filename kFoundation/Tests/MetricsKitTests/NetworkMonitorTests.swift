import XCTest
@testable import MetricsKit

final class StubNetworkStatsProvider: NetworkStatsProvider, @unchecked Sendable {
    private let stats: [InterfaceBytes]
    private var index = 0
    init(_ stats: [InterfaceBytes]) { self.stats = stats }
    func read() throws -> InterfaceBytes {
        defer { index += 1 }
        return stats[min(index, stats.count - 1)]
    }
}

final class TestClock: KWatchClock, @unchecked Sendable {
    private let times: [TimeInterval]
    private var index = 0
    init(_ times: [TimeInterval]) { self.times = times }
    func now() -> Date {
        defer { index += 1 }
        return Date(timeIntervalSince1970: times[min(index, times.count - 1)])
    }
}

final class NetworkMonitorTests: XCTestCase {
    func testNetworkReportsDeltaRate() async throws {
        let provider = StubNetworkStatsProvider([
            .init(receivedBytes: 100, sentBytes: 50),
            .init(receivedBytes: 300, sentBytes: 100)
        ])
        let monitor = NetworkMonitor(provider: provider, clock: TestClock([0, 2]))
        _ = try await monitor.sample()
        let sample = try await monitor.sample()
        XCTAssertEqual(sample.value, .bytesPerSecond(125))
    }

    func testFirstSampleReturnsZeroRate() async throws {
        let provider = StubNetworkStatsProvider([.init(receivedBytes: 1_000, sentBytes: 1_000)])
        let sample = try await NetworkMonitor(provider: provider, clock: TestClock([0])).sample()
        XCTAssertEqual(sample.value, .bytesPerSecond(0))
    }

    func testNetworkClampsCounterResetsToZero() async throws {
        let provider = StubNetworkStatsProvider([
            .init(receivedBytes: 1_000, sentBytes: 1_000),
            .init(receivedBytes: 100, sentBytes: 50)
        ])
        let monitor = NetworkMonitor(provider: provider, clock: TestClock([0, 1]))
        _ = try await monitor.sample()
        let sample = try await monitor.sample()
        XCTAssertEqual(sample.value, .bytesPerSecond(0))
    }
}
