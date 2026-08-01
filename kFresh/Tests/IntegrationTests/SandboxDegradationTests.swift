import XCTest
@testable import kFresh

final class SandboxDegradationTests: XCTestCase {
    func testAppModelWithoutFDA() {
        // InstalledApp should function without FDA (no residues populated)
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Test.app"),
            displayName: "Test",
            bundleID: "com.example.Test",
            version: "1.0",
            source: .userInstalled,
            isRunning: false,
            lastUsedDate: nil
        )
        XCTAssertEqual(app.displayName, "Test")
        XCTAssertEqual(app.source, .userInstalled)
        XCTAssertTrue(app.residues.isEmpty)
    }

    func testResidueDetectorGracefulDegradation() async {
        // Without FDA, residue detection should return empty, not crash
        let detector = ResidueDetector(ruleStore: nil)
        let residues = await detector.detectResidues(
            bundleID: "com.apple.TestApp",
            appName: "TestApp",
            appURL: URL(fileURLWithPath: "/Applications/TestApp.app")
        )
        // May or may not find residues depending on FDA status, but should never crash
        XCTAssertNotNil(residues)
    }

    func testProtectedAppListStillWorks() async {
        // Basic app listing should work regardless of FDA
        let catalog = AppCatalogService()
        let apps = await catalog.scan()
        let protectedApps = apps.filter { $0.isProtected }
        XCTAssertFalse(protectedApps.isEmpty)
    }

    @MainActor
    func testProGateBlocksWithoutPurchase() {
        // A fresh StoreManager defaults to free unless the test override key
        // says otherwise (set by setProForTesting / the -kFreshTestPro arg).
        defer { UserDefaults.standard.set(false, forKey: StoreManager.testOverrideKey) }
        let manager = StoreManager()
        XCTAssertEqual(manager.state, .free)
    }
}
