import XCTest
@testable import kUninstall

final class AppCatalogServiceTests: XCTestCase {
    func testClassifySourceSystem() async {
        let service = AppCatalogService()
        let source = await service.classifySource(
            url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
            bundleID: "com.apple.finder"
        )
        XCTAssertEqual(source, .system)
    }

    func testClassifySourceMAS() async {
        let service = AppCatalogService()
        let source = await service.classifySource(
            url: URL(fileURLWithPath: "/Applications/Xcode.app"),
            bundleID: "com.apple.dt.Xcode"
        )
        // Without a real receipt we expect .userInstalled or .unknown
        // This tests that /Applications/ paths resolve correctly
        XCTAssertNotEqual(source, .system)
    }

    func testAppSourceUnknown() async {
        let service = AppCatalogService()
        let source = await service.classifySource(
            url: URL(fileURLWithPath: "/tmp/test.app"),
            bundleID: "com.example.Test"
        )
        XCTAssertEqual(source, .unknown)
    }
}
