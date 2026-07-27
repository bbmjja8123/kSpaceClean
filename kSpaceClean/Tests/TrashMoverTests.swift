import XCTest
@testable import kSpaceClean

final class TrashMoverTests: XCTestCase {
    func test_trashResult_aggregation() {
        let snapshots = [
            TrashSnapshot(originalPath: "/tmp/a.txt", trashPath: "~/.Trash/a.txt", fileSize: 100, modifiedAt: Date()),
            TrashSnapshot(originalPath: "/tmp/b.txt", trashPath: "~/.Trash/b.txt", fileSize: 200, modifiedAt: Date()),
        ]
        let failed: [(URL, TrashMover.MoveError)] = [
            (URL(filePath: "/tmp/c.txt"), .fileNotFound(URL(filePath: "/tmp/c.txt"))),
        ]
        let result = TrashResult(snapshots: snapshots, failed: failed)

        XCTAssertEqual(result.succeeded.count, 2)
        XCTAssertEqual(result.failed.count, 1)
    }

    func test_trashResult_empty() {
        let result = TrashResult(snapshots: [], failed: [])
        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertTrue(result.failed.isEmpty)
    }
}
