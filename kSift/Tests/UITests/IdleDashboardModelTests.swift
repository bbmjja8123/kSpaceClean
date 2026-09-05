import XCTest
@testable import kSift

@MainActor
final class IdleDashboardModelTests: XCTestCase {
    func testLoadRecentScansMapsNewestThree() async throws {
        let records: [ScanRecord] = (0..<5).map { index in
            ScanRecord(
                id: UUID(),
                timestamp: Date(timeIntervalSinceNow: -Double(index) * 3_600),
                profileType: .developer,
                totalFilesScanned: 100 + index,
                totalDuplicatesFound: 10 + index,
                totalWasteSize: Int64(1_000 + index),
                duration: 5,
                groups: []
            )
        }
        let model = IdleDashboardModel(repository: MockDuplicateRepository(records: records))
        model.loadRecentScans()
        // loadRecentScans hops through a detached task; poll briefly.
        for _ in 0..<20 where model.recentScans.isEmpty {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(model.recentScans.count, 3, "Only the three most recent scans surface")
        XCTAssertEqual(model.recentScans[0].groupsFound, 10, "Newest record first")
        XCTAssertEqual(model.lastScanSummary?.wasteBytes, 1_000)
    }

    func testEmptyRepositoryLeavesNoReassurance() async throws {
        let model = IdleDashboardModel(repository: MockDuplicateRepository(records: []))
        model.loadRecentScans()
        for _ in 0..<20 where model.lastScanSummary != nil {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(model.recentScans.isEmpty)
        XCTAssertNil(model.lastScanSummary, "No prior scan → no reassurance card")
    }
}
