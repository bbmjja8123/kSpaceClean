import XCTest
@testable import kFresh

/// Tests for the StoreKit 2 ``StoreManager``.
///
/// These exercise only the deterministic, no-real-StoreKit surface: initial
/// state, the test override seam, launch-argument parsing, and entitlement
/// gating that honors the override. Real purchases/restores are covered by
/// manual StoreKit sandbox testing (Configuration.storekit in the scheme).
@MainActor
final class StoreManagerTests: XCTestCase {
    override func tearDown() async throws {
        // Reset the shared override key so it cannot leak into other tests.
        UserDefaults.standard.set(false, forKey: StoreManager.testOverrideKey)
    }

    func testInitialStateIsFree() {
        UserDefaults.standard.set(false, forKey: StoreManager.testOverrideKey)
        let manager = StoreManager()
        XCTAssertEqual(manager.state, .free)
    }

    func testSetProForTestingTransitionsToPro() {
        let manager = StoreManager()
        manager.setProForTesting(true)
        XCTAssertEqual(manager.state, .pro)
        manager.setProForTesting(false)
        XCTAssertEqual(manager.state, .free)
    }

    func testFreshManagerHonorsPersistedOverride() {
        UserDefaults.standard.set(true, forKey: StoreManager.testOverrideKey)
        let manager = StoreManager()
        XCTAssertEqual(manager.state, .pro)
    }

    func testParseTestProArgumentRecognizesTrueAndFalse() {
        XCTAssertTrue(StoreManager.parseTestProArgument(["-kFreshTestPro", "1"]))
        XCTAssertFalse(StoreManager.parseTestProArgument(["-kFreshTestPro", "0"]))
        XCTAssertFalse(StoreManager.parseTestProArgument([]))
        XCTAssertFalse(StoreManager.parseTestProArgument(["-kFreshTestPro"]))
    }

    func testIsProUnlockedHonorsOverride() async {
        UserDefaults.standard.set(true, forKey: StoreManager.testOverrideKey)
        defer { UserDefaults.standard.set(false, forKey: StoreManager.testOverrideKey) }
        let unlocked = await StoreManager.isProUnlocked()
        XCTAssertTrue(unlocked)
    }

    func testIsProUnlockedIsFalseWithoutOverrideOrEntitlements() async {
        UserDefaults.standard.set(false, forKey: StoreManager.testOverrideKey)
        let unlocked = await StoreManager.isProUnlocked()
        XCTAssertFalse(unlocked)
    }

    func testRefreshKeepsStateFreeWithoutEntitlements() async {
        UserDefaults.standard.set(false, forKey: StoreManager.testOverrideKey)
        let manager = StoreManager()
        await manager.refresh()
        XCTAssertEqual(manager.state, .free)
    }
}
