import XCTest
@testable import MetricsKit

final class StubDiskStatsProvider: DiskStatsProvider, @unchecked Sendable {
    private let stats: DiskStats
    init(_ stats: DiskStats) { self.stats = stats }
    func read(path: String) throws -> DiskStats { stats }
}

final class DiskMonitorTests: XCTestCase {
    func testDiskUsedPercentage() async throws {
        let provider = StubDiskStatsProvider(.init(totalBytes: 1_000, freeBytes: 250))
        let sample = try await DiskMonitor(path: "/", provider: provider).sample()
        XCTAssertEqual(sample.value, .percentage(75))
    }

    func testZeroTotalDiskReportsZeroWithoutCrash() async throws {
        let sample = try await DiskMonitor(path: "/", provider: StubDiskStatsProvider(.init(totalBytes: 0, freeBytes: 0))).sample()
        XCTAssertEqual(sample.value, .percentage(0))
    }
}
