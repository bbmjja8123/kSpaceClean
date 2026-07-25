import XCTest
@testable import kDupe

final class DirectoryDedupDetectorTests: XCTestCase {
    func testCrossDirectoryIdenticalFilesDetected() async throws {
        let detector = DirectoryDedupDetector()
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sub1 = dir.appendingPathComponent("dir_a")
        let sub2 = dir.appendingPathComponent("dir_b")
        try FileManager.default.createDirectory(at: sub1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sub2, withIntermediateDirectories: true)

        let file1 = try createTextFile(named: "common.txt", in: sub1, content: "same content")
        let file2 = try createTextFile(named: "common.txt", in: sub2, content: "same content")

        let groups = try await detector.detect([file1, file2], controller: controller)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.category, .directoryDedup)
        XCTAssertEqual(groups.first?.files.count, 2)
    }

    func testFilesInSameDirectoryNotGrouped() async throws {
        let detector = DirectoryDedupDetector()
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file1 = try createTextFile(named: "a.txt", in: dir, content: "same content")
        let file2 = try createTextFile(named: "b.txt", in: dir, content: "same content")

        let groups = try await detector.detect([file1, file2], controller: controller)
        XCTAssertTrue(groups.isEmpty, "Files in the same directory should not be grouped")
    }

    func testEmptyURLs() async throws {
        let detector = DirectoryDedupDetector()
        let controller = ScanController()
        let groups = try await detector.detect([], controller: controller)
        XCTAssertTrue(groups.isEmpty)
    }

    func testCancellationReturnsEarly() async throws {
        let detector = DirectoryDedupDetector()
        let controller = ScanController()
        controller.cancel()

        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = try createTextFile(named: "test.txt", in: dir, content: "data")

        let groups = try await detector.detect([file], controller: controller)
        XCTAssertTrue(groups.isEmpty, "Cancelled scan should return empty results")
    }
}
