import XCTest
@testable import kUninstall

final class TrashMoverTests: XCTestCase {
    func testCanMoveProtectedAppReturnsFalse() {
        let app = InstalledApp(url: URL(fileURLWithPath: "/System/Library/Finder.app"),
                                displayName: "Finder",
                                bundleID: "com.apple.finder",
                                version: "1.0",
                                source: .system,
                                isRunning: false,
                                lastUsedDate: nil)
        XCTAssertFalse(TrashMover.canMoveToTrash(app: app))
    }

    func testCanMoveUserAppReturnsTrue() {
        let app = InstalledApp(url: URL(fileURLWithPath: "/Applications/Test.app"),
                                displayName: "Test",
                                bundleID: "com.example.Test",
                                version: "1.0",
                                source: .userInstalled,
                                isRunning: false,
                                lastUsedDate: nil)
        XCTAssertTrue(TrashMover.canMoveToTrash(app: app))
    }
}
