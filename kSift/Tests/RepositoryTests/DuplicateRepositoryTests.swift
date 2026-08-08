import XCTest
@testable import kSift

final class DuplicateRepositoryTests: XCTestCase {
    func testSaveAndLoadRecords() async throws {
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storeURL = dir.appendingPathComponent("test_data.json")
        let repo = DuplicateRepositoryJSON(storeURL: storeURL)

        let record = ScanRecord(
            id: UUID(), timestamp: Date(), profileType: .developer,
            totalFilesScanned: 100, totalDuplicatesFound: 5,
            totalWasteSize: 1_024, duration: 2.5, groups: []
        )

        try await repo.saveScanRecord(record)

        let loaded = try await repo.loadScanRecords()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, record.id)
        XCTAssertEqual(loaded.first?.totalFilesScanned, 100)
        XCTAssertEqual(loaded.first?.totalDuplicatesFound, 5)
        XCTAssertEqual(loaded.first?.totalWasteSize, 1_024)
    }

    func testLoadNonExistentRecordReturnsNil() async throws {
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storeURL = dir.appendingPathComponent("empty.json")
        let repo = DuplicateRepositoryJSON(storeURL: storeURL)

        let result = try await repo.loadScanRecord(id: UUID())
        XCTAssertNil(result)
    }

    func testDeleteRecord() async throws {
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storeURL = dir.appendingPathComponent("delete_test.json")
        let repo = DuplicateRepositoryJSON(storeURL: storeURL)

        let record1 = ScanRecord(
            id: UUID(), timestamp: Date(), profileType: .developer,
            totalFilesScanned: 50, totalDuplicatesFound: 3,
            totalWasteSize: 512, duration: 1.0, groups: []
        )
        let record2 = ScanRecord(
            id: UUID(), timestamp: Date(), profileType: .simple,
            totalFilesScanned: 30, totalDuplicatesFound: 1,
            totalWasteSize: 256, duration: 0.5, groups: []
        )

        try await repo.saveScanRecord(record1)
        try await repo.saveScanRecord(record2)

        // Delete the first record
        try await repo.deleteScanRecord(id: record1.id)

        let remaining = try await repo.loadScanRecords()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, record2.id)
    }

    func testDeleteNonExistentRecordDoesNotThrow() async throws {
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storeURL = dir.appendingPathComponent("noop_delete.json")
        let repo = DuplicateRepositoryJSON(storeURL: storeURL)

        // Should not throw when deleting an ID that was never saved.
        try await repo.deleteScanRecord(id: UUID())

        let records = try await repo.loadScanRecords()
        XCTAssertTrue(records.isEmpty)
    }

    func testMultipleRecordsRoundTrip() async throws {
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storeURL = dir.appendingPathComponent("multi_test.json")
        let repo = DuplicateRepositoryJSON(storeURL: storeURL)

        let ids = (0..<5).map { _ in UUID() }
        for i in 0..<5 {
            let record = ScanRecord(
                id: ids[i], timestamp: Date(), profileType: .developer,
                totalFilesScanned: i * 10, totalDuplicatesFound: i,
                totalWasteSize: Int64(i * 100), duration: 1.0, groups: []
            )
            try await repo.saveScanRecord(record)
        }

        let all = try await repo.loadScanRecords()
        XCTAssertEqual(all.count, 5)

        // Most recently saved should be first
        XCTAssertEqual(all[0].id, ids[4])
        XCTAssertEqual(all[0].totalFilesScanned, 40)
    }

    func testLoadRecordByID() async throws {
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storeURL = dir.appendingPathComponent("load_by_id.json")
        let repo = DuplicateRepositoryJSON(storeURL: storeURL)

        let targetID = UUID()
        let record = ScanRecord(
            id: targetID, timestamp: Date(), profileType: .photographer,
            totalFilesScanned: 200, totalDuplicatesFound: 15,
            totalWasteSize: 10_240, duration: 3.0, groups: []
        )
        try await repo.saveScanRecord(record)

        let loaded = try await repo.loadScanRecord(id: targetID)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, targetID)
        XCTAssertEqual(loaded?.profileType, .photographer)

        // Non-matching ID returns nil
        let missing = try await repo.loadScanRecord(id: UUID())
        XCTAssertNil(missing)
    }

    func testEmptyStoreReturnsEmptyArray() async throws {
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storeURL = dir.appendingPathComponent("fresh.json")
        let repo = DuplicateRepositoryJSON(storeURL: storeURL)

        let records = try await repo.loadScanRecords()
        XCTAssertTrue(records.isEmpty)
    }
}
