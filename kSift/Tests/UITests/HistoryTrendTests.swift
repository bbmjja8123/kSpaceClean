import XCTest
@testable import kSift

final class HistoryTrendTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        c.firstWeekday = 2 // Monday, matching typical locale expectations
        calendar = c
        // A known Wednesday: 2026-09-02 12:00 +08:00.
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 2
        components.hour = 12; components.minute = 0
        now = c.date(from: components)
    }

    private func record(daysAgo: Double, bytes: Int64) -> ScanRecord {
        ScanRecord(
            id: UUID(),
            timestamp: now.addingTimeInterval(-daysAgo * 86_400),
            profileType: .developer,
            totalFilesScanned: 10,
            totalDuplicatesFound: 2,
            totalWasteSize: bytes,
            duration: 3,
            groups: []
        )
    }

    func testEmptyInputYieldsEightZeroPoints() {
        let points = HistoryViewModel.bucket(records: [], calendar: calendar, now: now)
        XCTAssertEqual(points.count, 8, "Honest gaps: 8 weeks even with no records")
        XCTAssertTrue(points.allSatisfy { $0.reclaimedBytes == 0 && $0.scanCount == 0 })
        // Oldest first.
        XCTAssertTrue(points[0].weekStart < points[7].weekStart)
    }

    func testRecordsBucketIntoTheirWeek() {
        // Both timestamps inside the current week (now is a Wednesday).
        let a = record(daysAgo: 1, bytes: 100)
        let b = record(daysAgo: 2, bytes: 250)
        let points = HistoryViewModel.bucket(records: [a, b], calendar: calendar, now: now)
        XCTAssertEqual(points.last?.reclaimedBytes, 350)
        XCTAssertEqual(points.last?.scanCount, 2)
        // Earlier weeks are zero.
        XCTAssertTrue(points.dropLast().allSatisfy { $0.reclaimedBytes == 0 })
    }

    func testMonthBoundaryRollsIntoCorrectWeek() {
        // ~5 weeks ago — before the 8-week window but well-separated.
        let old = record(daysAgo: 40, bytes: 500)
        let points = HistoryViewModel.bucket(records: [old], calendar: calendar, now: now)
        XCTAssertEqual(points.filter { $0.reclaimedBytes == 500 }.count, 1,
                       "Old-but-in-window record lands in exactly one bucket")
        // Older than 8 weeks is dropped entirely.
        let ancient = record(daysAgo: 90, bytes: 9_000)
        let pointsAncient = HistoryViewModel.bucket(records: [ancient], calendar: calendar, now: now)
        XCTAssertTrue(pointsAncient.allSatisfy { $0.reclaimedBytes == 0 })
    }

    func testDistributionSumsPerCategory() {
        let groupA = DuplicateGroup.mock(category: .perceptual, totalSize: 300, fileCount: 2)
        let groupB = DuplicateGroup.mock(category: .identical, totalSize: 700, fileCount: 2)
        let record = ScanRecord(
            id: UUID(), timestamp: now, profileType: .designer,
            totalFilesScanned: 4, totalDuplicatesFound: 4,
            totalWasteSize: 1_000, duration: 5, groups: [groupA, groupB]
        )
        let distribution = HistoryViewModel.categoryDistribution(records: [record])
        XCTAssertEqual(distribution[.perceptual], 300)
        XCTAssertEqual(distribution[.identical], 700)

        // Second record accumulates into the same categories.
        let groupA2 = DuplicateGroup.mock(category: .perceptual, totalSize: 100, fileCount: 2)
        let record2 = ScanRecord(
            id: UUID(), timestamp: now, profileType: .designer,
            totalFilesScanned: 2, totalDuplicatesFound: 2,
            totalWasteSize: 100, duration: 5, groups: [groupA2]
        )
        let combined = HistoryViewModel.categoryDistribution(records: [record, record2])
        XCTAssertEqual(combined[.perceptual], 400)
        XCTAssertEqual(combined[.identical], 700)
    }
}
