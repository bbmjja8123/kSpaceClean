import XCTest
@testable import kDupe

final class LargeFileDetectorTests: XCTestCase {
    func testFilesAboveThresholdDetected() async throws {
        let threshold: Int64 = 10
        let detector = LargeFileDetector(threshold: threshold)
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createTempFile(named: "large.bin", in: dir, withSize: 100)

        let groups = await detector.detect([dir.appendingPathComponent("large.bin")], controller: controller)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.category, .largeFile)
        XCTAssertEqual(groups.first?.fileCount, 1)
    }

    func testFilesBelowThresholdExcluded() async throws {
        let threshold: Int64 = 100
        let detector = LargeFileDetector(threshold: threshold)
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createTempFile(named: "small.bin", in: dir, withSize: 10)

        let groups = await detector.detect([dir.appendingPathComponent("small.bin")], controller: controller)
        XCTAssertTrue(groups.isEmpty, "Files below threshold should be excluded")
    }

    func testCustomThreshold() async throws {
        let threshold: Int64 = 50
        let detector = LargeFileDetector(threshold: threshold)
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createTempFile(named: "medium.bin", in: dir, withSize: 30)
        try createTempFile(named: "big.bin", in: dir, withSize: 100)

        let mediumURL = dir.appendingPathComponent("medium.bin")
        let bigURL = dir.appendingPathComponent("big.bin")
        let groups = await detector.detect([mediumURL, bigURL], controller: controller)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.files.first?.url.lastPathComponent, "big.bin")
        XCTAssertEqual(groups.first?.totalSize, 100)
    }

    func testEmptyURLs() async throws {
        let detector = LargeFileDetector(threshold: 10)
        let controller = ScanController()
        let groups = await detector.detect([], controller: controller)
        XCTAssertTrue(groups.isEmpty)
    }

    func testCancellationReturnsEarly() async throws {
        let detector = LargeFileDetector(threshold: 1)
        let controller = ScanController()
        controller.cancel()

        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try createTempFile(named: "big.bin", in: dir, withSize: 999)

        let groups = await detector.detect([dir.appendingPathComponent("big.bin")], controller: controller)
        XCTAssertTrue(groups.isEmpty, "Cancelled scan should return empty results")
    }
}
