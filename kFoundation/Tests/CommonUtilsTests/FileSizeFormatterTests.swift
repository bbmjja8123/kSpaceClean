import XCTest
@testable import CommonUtils

final class FileSizeFormatterTests: XCTestCase {
    func testAbbreviatedBytes() {
        XCTAssertEqual(FileSizeFormatter.abbreviated(from: 0), "0 B")
        XCTAssertEqual(FileSizeFormatter.abbreviated(from: 500), "500 B")
    }

    func testAbbreviatedKB() {
        XCTAssertEqual(FileSizeFormatter.abbreviated(from: 2048), "2.0 KB")
    }

    func testAbbreviatedMB() {
        XCTAssertEqual(FileSizeFormatter.abbreviated(from: 5_242_880), "5.0 MB")
    }

    func testAbbreviatedGB() {
        let result = FileSizeFormatter.abbreviated(from: 10_737_418_240)
        XCTAssertTrue(result.hasSuffix("GB"))
    }

    func testCategoryColorMapping() {
        XCTAssertEqual(FileCategory.image.color, Color(hex: "#A855F7"))
        XCTAssertEqual(FileCategory.video.color, Color(hex: "#3B82F6"))
    }
}
