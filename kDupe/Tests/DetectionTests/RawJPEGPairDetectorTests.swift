import XCTest
@testable import kDupe

final class RawJPEGPairDetectorTests: XCTestCase {
    func testBasicPairDetected() async throws {
        let detector = RawJPEGPairDetector()
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createTempFile(named: "photo.raf", in: dir, withSize: 5000)
        try createTempFile(named: "photo.jpg", in: dir, withSize: 500)

        let urls = [
            dir.appendingPathComponent("photo.raf"),
            dir.appendingPathComponent("photo.jpg"),
        ]
        let groups = await detector.detect(urls, controller: controller)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.category, .rawJPEG)
        XCTAssertEqual(groups.first?.files.count, 2)
    }

    func testAllRAWExtensionsPaired() async throws {
        let detector = RawJPEGPairDetector()
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let rawExts = ["raf", "cr2", "nef", "arw", "dng", "orf"]
        var urls: [URL] = []
        for ext in rawExts {
            try createTempFile(named: "img.\(ext)", in: dir, withSize: 5000)
            urls.append(dir.appendingPathComponent("img.\(ext)"))
        }
        try createTempFile(named: "img.jpg", in: dir, withSize: 500)
        urls.append(dir.appendingPathComponent("img.jpg"))

        let groups = await detector.detect(urls, controller: controller)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.files.count, 7) // 6 raw + 1 jpeg
    }

    func testJPEGVariants() async throws {
        let detector = RawJPEGPairDetector()
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createTempFile(named: "vacation.raf", in: dir, withSize: 5000)
        try createTempFile(named: "vacation.jpeg", in: dir, withSize: 500)
        try createTempFile(named: "vacation.jpe", in: dir, withSize: 400)

        let urls = [
            dir.appendingPathComponent("vacation.raf"),
            dir.appendingPathComponent("vacation.jpeg"),
            dir.appendingPathComponent("vacation.jpe"),
        ]
        let groups = await detector.detect(urls, controller: controller)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.files.count, 3)
    }

    func testUnmatchedRawFileExcluded() async throws {
        let detector = RawJPEGPairDetector()
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createTempFile(named: "orphan.raf", in: dir, withSize: 5000)

        let groups = await detector.detect([dir.appendingPathComponent("orphan.raf")], controller: controller)
        XCTAssertTrue(groups.isEmpty, "Unmatched RAW file without JPEG should not produce a group")
    }

    func testUnmatchedJPEGFileExcluded() async throws {
        let detector = RawJPEGPairDetector()
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createTempFile(named: "alone.jpg", in: dir, withSize: 500)

        let groups = await detector.detect([dir.appendingPathComponent("alone.jpg")], controller: controller)
        XCTAssertTrue(groups.isEmpty, "Unmatched JPEG without RAW should not produce a group")
    }

    func testEmptyURLs() async throws {
        let detector = RawJPEGPairDetector()
        let controller = ScanController()
        let groups = await detector.detect([], controller: controller)
        XCTAssertTrue(groups.isEmpty)
    }

    func testCancellationReturnsEarly() async throws {
        let detector = RawJPEGPairDetector()
        let controller = ScanController()
        controller.cancel()

        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try createTempFile(named: "photo.raf", in: dir, withSize: 5000)
        try createTempFile(named: "photo.jpg", in: dir, withSize: 500)

        let urls = [
            dir.appendingPathComponent("photo.raf"),
            dir.appendingPathComponent("photo.jpg"),
        ]
        let groups = await detector.detect(urls, controller: controller)
        XCTAssertTrue(groups.isEmpty, "Cancelled scan should return empty results")
    }
}
