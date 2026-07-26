import XCTest

/// Skeleton UI tests covering the launch and menu-bar paths for kWatch.
///
/// These tests are designed to run against the production kWatch.app with
/// the `-reset-preferences` and `-ui-testing` launch arguments wired up in
/// `kWatchAppDelegate.applicationDidFinishLaunching(_:)`. The
/// `-reset-preferences` argument forces the onboarding flag to its initial
/// state so the first-launch flow always appears.
final class KWatchLaunchTests: XCTestCase {

    /// First launch shows the onboarding window; after tapping "Get
    /// Started" and relaunching, the menu-bar extra is reachable.
    func testFirstLaunchShowsOnboardingAndSecondLaunchShowsMenuBar() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-reset-preferences"]
        app.launch()

        // Onboarding window is the first thing the user sees.
        let welcomeText = app.staticTexts["Welcome to kWatch"]
        XCTAssertTrue(
            welcomeText.waitForExistence(timeout: 5),
            "Onboarding welcome text 'Welcome to kWatch' did not appear within 5s"
        )

        let getStartedButton = app.buttons["Get Started"]
        XCTAssertTrue(getStartedButton.exists, "Onboarding 'Get Started' button missing")
        getStartedButton.click()

        // Relaunch — the onboarding flag should now be set and the app
        // should boot straight into the menu-bar architecture.
        app.terminate()
        app.launchArguments += ["-ui-testing"]
        app.launch()

        // Verify the menu-bar item exists. `statusItems` is the public
        // accessibility hook for `NSStatusItem` / `MenuBarExtra`.
        let menuBarItem = app.statusItems["kWatch"]
        XCTAssertTrue(
            menuBarItem.waitForExistence(timeout: 5),
            "Menu-bar item 'kWatch' did not appear on second launch"
        )
    }
}