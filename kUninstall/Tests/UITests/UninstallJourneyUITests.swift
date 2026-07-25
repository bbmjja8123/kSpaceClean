import XCTest

final class UninstallJourneyUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }

    func testMainWindowShowsAppList() {
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    func testSettingsOpens() {
        #if DEBUG
        app.menuBars.menuBarItems["Settings"].click()
        XCTAssertTrue(app.sheets.firstMatch.exists)
        #endif
    }

    func testPaywallShowsProFeatures() {
        app.buttons["升级 Pro"].click()
        let paywall = app.sheets["PaywallView"]
        XCTAssertTrue(paywall.waitForExistence(timeout: 3))
    }
}
