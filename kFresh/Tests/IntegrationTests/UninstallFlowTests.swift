import XCTest
@testable import kFresh

final class UninstallFlowTests: XCTestCase {
    func testScanToResidueFlow() async {
        let scanner = ResidueScanner()
        let apps = await scanner.scanAll()
        XCTAssertFalse(apps.isEmpty)
        let hasResidues = apps.contains { !$0.residues.isEmpty }
        print("Apps: \(apps.count), any residues: \(hasResidues)")
    }

    func testProtectedAppCannotBeUninstalled() {
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/System/Library/Finder.app"),
            displayName: "Finder",
            bundleID: "com.apple.finder",
            version: "1.0",
            source: .system,
            isRunning: false,
            lastUsedDate: nil
        )
        XCTAssertFalse(TrashMover.canMoveToTrash(app: app))
    }

    func testUserAppCanBeUninstalled() {
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Test.app"),
            displayName: "Test",
            bundleID: "com.example.Test",
            version: "1.0",
            source: .userInstalled,
            isRunning: false,
            lastUsedDate: nil
        )
        XCTAssertTrue(TrashMover.canMoveToTrash(app: app))
    }

    func testScanReturnsInstalledApps() async {
        let catalog = AppCatalogService()
        let apps = await catalog.scan()
        XCTAssertFalse(apps.isEmpty)
        for app in apps {
            XCTAssertFalse(app.bundleID.isEmpty)
            XCTAssertFalse(app.displayName.isEmpty)
        }
    }
}
