import XCTest
@testable import MetricsKit

final class StubCPUStatsProvider: CPUStatsProvider, @unchecked Sendable {
    private let stats: [CPUStats]
    private var index = 0
    init(_ stats: [CPUStats]) { self.stats = stats }
    func read() throws -> CPUStats {
        defer { index += 1 }
        return stats[min(index, stats.count - 1)]
    }
}

final class CPUMonitorTests: XCTestCase {
    func testCPUUsesDeltasInsteadOfAbsoluteTicks() async throws {
        let provider = StubCPUStatsProvider([
            .init(user: 10, system: 10, idle: 80),
            .init(user: 20, system: 20, idle: 80)
        ])
        let monitor = CPUMonitor(provider: provider)
        _ = try await monitor.sample()
        let sample = try await monitor.sample()
        // totalDelta = (120 - 100) = 20, idleDelta = 0
        // usage = (20 - 0) / 20 * 100 = 100% (idle ticks did not grow between samples)
        XCTAssertEqual(sample.value, .percentage(100))
    }

    func testFirstSampleReturnsZeroWithoutPreviousReference() async throws {
        let provider = StubCPUStatsProvider([.init(user: 5, system: 5, idle: 90)])
        let sample = try await CPUMonitor(provider: provider).sample()
        XCTAssertEqual(sample.value, .percentage(0))
    }
}