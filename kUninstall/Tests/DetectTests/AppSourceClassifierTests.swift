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
        // Apple app outside /System/ with com.apple. prefix and no MAS receipt
        let service = AppCatalogService()
        let result = service.classifySource(
            url: URL(fileURLWithPath: "/Applications/TextEdit.app"),
            bundleID: "com.apple.TextEdit"
        )
        XCTAssertEqual(result, .appleBuiltIn)
    }

    func testMASApp() {
        // Create a temp directory simulating an App Store app with receipt
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.kraftly.mastest")
        try? FileManager.default.removeItem(at: tmpDir)
        try? FileManager.default.createDirectory(
            at: tmpDir.appendingPathComponent("Contents/_MASReceipt"),
            withIntermediateDirectories: true
        )
        // Create the receipt file (required by hasMASReceipt check)
        try? Data().write(to: tmpDir.appendingPathComponent("Contents/_MASReceipt/receipt"))

        let service = AppCatalogService()
        let result = service.classifySource(
            url: tmpDir,
            bundleID: "com.kraftly.MASApp"
        )
        XCTAssertEqual(result, .mas)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testProtectedBundleID() {
        XCTAssertTrue(InstalledApp.isBundleIDProtected("com.apple.finder"))
        XCTAssertTrue(InstalledApp.isBundleIDProtected("com.apple.Terminal"))
        XCTAssertTrue(InstalledApp.isBundleIDProtected("com.apple.dock"))
        XCTAssertFalse(InstalledApp.isBundleIDProtected("com.example.Test"))
    }
}
