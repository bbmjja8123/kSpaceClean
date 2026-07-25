import XCTest
@testable import kDupe

final class ByteIdenticalDetectorTests: XCTestCase {
    func testIdenticalFilesDetected() async throws {
        let detector = ByteIdenticalDetector()
        let controller = ScanController()

        // Create temp files with identical content
        let dir = FileManager.default.temporaryDirectory
        let file1 = dir.appendingPathComponent("test1.txt")
        let file2 = dir.appendingPathComponent("test2.txt")
        try "hello".write(to: file1, atomically: true, encoding: .utf8)
        try "hello".write(to: file2, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: file1)
            try? FileManager.default.removeItem(at: file2)
        }

        let groups = try await detector.detect([file1, file2], controller: controller)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.files.count, 2)
    }
}
