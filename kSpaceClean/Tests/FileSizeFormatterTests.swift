import XCTest
@testable import kSpaceClean
import CommonUtils

final class FileSizeFormatterTests: XCTestCase {
    func test_stringFromBytes() {
        XCTAssertEqual(FileSizeFormatter.string(from: 0), "Zero KB")
        XCTAssertEqual(FileSizeFormatter.string(from: 500), "500 bytes")
        XCTAssertTrue(FileSizeFormatter.string(from: 1024).contains("KB"))
    }

    func test_abbreviatedFromBytes() {
        XCTAssertEqual(FileSizeFormatter.abbreviated(from: 0), "0 B")
        XCTAssertEqual(FileSizeFormatter.abbreviated(from: 1024), "1.0 KB")
        XCTAssertEqual(FileSizeFormatter.abbreviated(from: 1_048_576), "1.0 MB")
        XCTAssertEqual(FileSizeFormatter.abbreviated(from: 1_073_741_824), "1.0 GB")
    }

    func test_abbreviatedRounding() {
        let result = FileSizeFormatter.abbreviated(from: 1_500_000) // ~1.43 MB
        XCTAssertTrue(result.contains("MB"))
    }
}
