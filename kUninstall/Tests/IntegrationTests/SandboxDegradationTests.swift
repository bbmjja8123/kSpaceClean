import XCTest
@testable import kUninstall

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
        let detector = ResidueDetector()
        let residues = await detector.detectResidues(bundleID: "com.apple.TestApp", appName: "TestApp")
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

    func testProGateBlocksWithoutPurchase() async {
        // StoreManager should default to not Pro before any purchase
        let isPro = await StoreManager.shared.isPro
        XCTAssertFalse(isPro)
    }
}
