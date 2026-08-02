import XCTest

/// Smoke test that kFresh launches and reaches its root view. Lives in the
/// UI-test bundle (`kFreshUITests`) and exercises the real app entry point
/// end-to-end via XCUIApplication.
final class AppLaunchUITests: XCTestCase {
    func testAppLaunchesToRootView() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5),
                      "kFresh should launch into the foreground")
    }
}
