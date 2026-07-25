import XCTest
@testable import kUninstall

final class AppSourceClassifierTests: XCTestCase {
    func testSystemPath() {
        let service = AppCatalogService()
        let result = service.classifySource(
            url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
            bundleID: "com.apple.finder"
        )
        XCTAssertEqual(result, .system)
    }

    func testUserInstalled() {
        let service = AppCatalogService()
        let result = service.classifySource(
            url: URL(fileURLWithPath: "/Applications/Test.app"),
            bundleID: "com.example.Test"
        )
        XCTAssertEqual(result, .userInstalled)
    }

    func testAppleBuiltIn() {
        let service = AppCatalogService()
        let result = service.classifySource(
            url: URL(fileURLWithPath: "/System/Applications/Calendar.app"),
            bundleID: "com.apple.iCal"
        )
        XCTAssertEqual(result, .appleBuiltIn)
    }

    func testMASApp() {
        let service = AppCatalogService()
        let result = service.classifySource(
            url: URL(fileURLWithPath: "/Applications/Pages.app"),
            bundleID: "com.apple.Pages"
        )
        XCTAssertEqual(result, .mas)
    }

    func testProtectedBundleID() {
        XCTAssertTrue(InstalledApp.isBundleIDProtected("com.apple.finder"))
        XCTAssertTrue(InstalledApp.isBundleIDProtected("com.apple.Terminal"))
        XCTAssertTrue(InstalledApp.isBundleIDProtected("com.apple.dock"))
        XCTAssertFalse(InstalledApp.isBundleIDProtected("com.example.Test"))
    }
}
