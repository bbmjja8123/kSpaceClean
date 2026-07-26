import XCTest

/// Skeleton UI test covering the free-tier paywall journey.
///
/// Free users must be able to see the Dashboard with the basic metrics
/// (CPU/Memory/Disk/Network), but any attempt to enter a Pro-gated screen
/// (History, Processes, Alerts, or threshold configuration) must surface
/// the paywall with the correct headline and price line.
final class KWatchPurchaseJourneyTests: XCTestCase {

    /// Launching the app as a Free user and tapping a Pro-gated action
    /// shows the paywall with the expected copy.
    func testFreeUserSeesPaywallCopy() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-reset-preferences", "-free-user"]
        app.launch()

        // Dismiss onboarding if it appears (it should because of
        // `-reset-preferences`). The onboarding flow ends with the user
        // landing in the dashboard.
        if app.staticTexts["Welcome to kWatch"].waitForExistence(timeout: 3) {
            app.buttons["Get Started"].click()
        }

        // Open the dashboard through the menu bar so we have a known-good
        // surface to act on.
        let menuBarItem = app.statusItems["kWatch"]
        XCTAssertTrue(menuBarItem.waitForExistence(timeout: 5), "Menu-bar item missing")
        menuBarItem.click()

        // Free users see the History / Processes / Alerts entries in the
        // menu; tapping any of them triggers the paywall. We use the
        // navigation button that opens the History view as the canonical
        // Pro-gated action.
        let historyButton = app.buttons["History"]
        XCTAssertTrue(historyButton.waitForExistence(timeout: 5), "History nav button missing")
        historyButton.click()

        // The paywall sheet contains "kWatch Pro" and the price line.
        let paywallHeadline = app.staticTexts["kWatch Pro"]
        XCTAssertTrue(
            paywallHeadline.waitForExistence(timeout: 5),
            "Paywall headline 'kWatch Pro' did not appear"
        )

        let priceLine = app.staticTexts["$7.99 one-time purchase"]
        XCTAssertTrue(
            priceLine.waitForExistence(timeout: 3),
            "Paywall price '$7.99 one-time purchase' missing"
        )

        // Restore Purchases + Not Now should both be present so the user
        // has an escape hatch.
        XCTAssertTrue(app.buttons["Restore Purchases"].exists, "Restore Purchases button missing")
        XCTAssertTrue(app.buttons["Not Now"].exists, "Not Now dismiss button missing")
    }
}