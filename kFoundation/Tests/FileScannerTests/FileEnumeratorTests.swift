import XCTest
@testable import FileScanner

final class FileEnumeratorTests: XCTestCase {
    func testCancellationToken() {
        let token = CancellationToken()
        XCTAssertFalse(token.isCancelled)
        token.cancel()
        XCTAssertTrue(token.isCancelled)
    }
}
