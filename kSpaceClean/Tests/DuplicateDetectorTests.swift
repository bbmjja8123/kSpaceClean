import XCTest
@testable import kSpaceClean
import FileScanner

final class DuplicateDetectorTests: XCTestCase {
    func test_emptyFiles_noDuplicates() async {
        let detector = DuplicateDetector()
        let candidates = await detector.candidates()
        XCTAssertTrue(candidates.isEmpty)
    }

    func test_uniqueFiles_noDuplicates() async {
        let detector = DuplicateDetector()
        await detector.add(file: URL(filePath: "/a.txt"), size: 100)
        await detector.add(file: URL(filePath: "/b.txt"), size: 200)
        let candidates = await detector.candidates()
        XCTAssertTrue(candidates.isEmpty)
    }

    func test_duplicateCandidates_found() async {
        let detector = DuplicateDetector()
        await detector.add(file: URL(filePath: "/a.txt"), size: 100)
        await detector.add(file: URL(filePath: "/b.txt"), size: 100)
        let candidates = await detector.candidates()
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.size, 100)
        XCTAssertEqual(candidates.first?.urls.count, 2)
    }
}
