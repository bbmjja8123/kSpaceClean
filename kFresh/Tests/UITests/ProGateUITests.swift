import XCTest
@testable import kFresh

/// Controller-level UI contract tests for the Pro gate.
///
/// This bundle hosts no dedicated UI test target (it is a unit bundle hosted
/// inside kFresh.app), so `XCUIApplication()` cannot launch a second copy of
/// the app. Instead these guard the launch-argument → UserDefaults →
/// ``StoreManager`` wiring that `kFreshApp.init()` performs, which a real UI
/// test target will exercise end-to-end once one exists.
@MainActor
final class ProGateUITests: XCTestCase {
    override func tearDown() async throws {
        // Reset the shared override key so it cannot leak into other tests.
        UserDefaults.standard.set(false, forKey: StoreManager.testOverrideKey)
    }

    /// `-kFreshTestPro 1` must flip the override on.
    func testLaunchArgument1EnablesProOverride() {
        let args = ["-kFreshTestPro", "1"]
        XCTAssertTrue(StoreManager.parseTestProArgument(args))
        UserDefaults.standard.set(StoreManager.parseTestProArgument(args), forKey: StoreManager.testOverrideKey)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: StoreManager.testOverrideKey))
    }

    /// `-kFreshTestPro 0` must leave the override off.
    func testLaunchArgument0LeavesOverrideDisabled() {
        let args = ["-kFreshTestPro", "0"]
        XCTAssertFalse(StoreManager.parseTestProArgument(args))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: StoreManager.testOverrideKey))
    }

    /// With the launch argument applied, the gate must read as unlocked.
    func testStoreManagerReflectsOverrideFromLaunchArgument() {
        let args = ["-kFreshTestPro", "1"]
        UserDefaults.standard.set(StoreManager.parseTestProArgument(args), forKey: StoreManager.testOverrideKey)
        let manager = StoreManager()
        XCTAssertEqual(manager.state, .pro)
    }
}
