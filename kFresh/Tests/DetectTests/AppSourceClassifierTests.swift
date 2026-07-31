import XCTest
@testable import kFresh

final class AppSourceClassifierTests: XCTestCase {
    func testSystemPath() {
        let result = AppCatalogService.classifySource(
            url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
            bundleID: "com.apple.finder"
        )
        XCTAssertEqual(result, .system)
    }

    func testUserInstalled() {
        let result = AppCatalogService.classifySource(
            url: URL(fileURLWithPath: "/Applications/Test.app"),
            bundleID: "com.example.Test"
        )
        XCTAssertEqual(result, .userInstalled)
    }

    func testAppleBuiltIn() {
        // Apple app outside /System/ with com.apple. prefix and no MAS receipt
        let result = AppCatalogService.classifySource(
            url: URL(fileURLWithPath: "/Applications/TextEdit.app"),
            bundleID: "com.apple.TextEdit"
        )
        XCTAssertEqual(result, .appleBuiltIn)
    }

    func testMASApp() throws {
        // Create a temp directory simulating an App Store app with receipt
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.kraftly.mastest")
        // `removeItem` throws when the directory does not exist (which is the
        // common case on first run). Only remove if present so the test is
        // idempotent across runs without a tearDown.
        if FileManager.default.fileExists(atPath: tmpDir.path) {
            try FileManager.default.removeItem(at: tmpDir)
        }
        try FileManager.default.createDirectory(
            at: tmpDir.appendingPathComponent("Contents/_MASReceipt"),
            withIntermediateDirectories: true
        )
        // Create the receipt file (required by hasMASReceipt check)
        try Data().write(to: tmpDir.appendingPathComponent("Contents/_MASReceipt/receipt"))

        let result = AppCatalogService.classifySource(
            url: tmpDir,
            bundleID: "com.kraftly.MASApp"
        )
        XCTAssertEqual(result, .mas)

        try FileManager.default.removeItem(at: tmpDir)
    }

    func testProtectedBundleID() {
        XCTAssertTrue(InstalledApp.isBundleIDProtected("com.apple.finder"))
        XCTAssertTrue(InstalledApp.isBundleIDProtected("com.apple.Terminal"))
        XCTAssertTrue(InstalledApp.isBundleIDProtected("com.apple.dock"))
        XCTAssertFalse(InstalledApp.isBundleIDProtected("com.example.Test"))
    }
}
