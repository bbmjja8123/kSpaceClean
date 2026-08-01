import XCTest
@testable import kFresh

final class InstalledAppTests: XCTestCase {
    func testAppSourceClassification() {
        let systemApp = InstalledApp(url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
                                      displayName: "Finder",
                                      bundleID: "com.apple.finder",
                                      version: "1.0",
                                      source: .system)
        XCTAssertEqual(systemApp.source, .system)
        XCTAssertTrue(systemApp.isProtected)
    }

    func testResidueConfidenceOrdering() {
        let high = ResidueFile(url: URL(fileURLWithPath: "~/Library/Preferences/com.example.plist"),
                                type: .preferences,
                                sizeBytes: 100,
                                confidence: 0.99)
        let low = ResidueFile(url: URL(fileURLWithPath: "~/Library/Caches/com.example/"),
                               type: .caches,
                               sizeBytes: 200,
                               confidence: 0.5)
        XCTAssertGreaterThan(high.confidence, low.confidence)
    }

    func testProtectedBundleIDs() {
        let safe = InstalledApp.isBundleIDProtected("com.example.Foo")
        let protected = InstalledApp.isBundleIDProtected("com.apple.finder")
        XCTAssertFalse(safe)
        XCTAssertTrue(protected)
    }
}
