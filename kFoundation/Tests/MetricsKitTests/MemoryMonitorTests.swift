import XCTest
@testable import MetricsKit

final class StubMemoryStatsProvider: MemoryStatsProvider, @unchecked Sendable {
    private let total: UInt64
    private let active: UInt64
    init(total: UInt64, active: UInt64) { self.total = total; self.active = active }
    func read() throws -> MemoryStats { .init(totalBytes: total, activeBytes: active) }
}

final class MemoryMonitorTests: XCTestCase {
    func testMemoryReportsActivePercentage() async throws {
        let provider = StubMemoryStatsProvider(total: 100, active: 60)
        let sample = try await MemoryMonitor(provider: provider).sample()
        XCTAssertEqual(sample.value, .percentage(60))
    }

    func testZeroTotalMemoryReportsZeroWithoutCrash() async throws {
        let sample = try await MemoryMonitor(provider: StubMemoryStatsProvider(total: 0, active: 0)).sample()
        XCTAssertEqual(sample.value, .percentage(0))
    }
}