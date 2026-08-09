import XCTest
@testable import kFresh

/// Coordinator-level tests for the DeepClean + StartupItems sheet flags
/// added by the G-KF-01 P0 fix. These complement ``OnboardingRoutingTests``:
/// onboarding owns the `showOnboarding` flag; these own the new Pro-tool
/// sheet flags and their default state.
@MainActor
final class AppCoordinatorNavigationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "AppCoordinatorNavigationTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    // MARK: - Defaults

    /// Both sheet flags default to `false` so an app launch with no pending
    /// deep link shows no Pro-tool sheet floating over the app list.
    func testDeepCleanAndStartupFlagsStartHidden() {
        let coordinator = AppCoordinator(defaults: defaults)
        XCTAssertFalse(coordinator.showDeepClean)
        XCTAssertFalse(coordinator.showStartupItems)
    }

    // MARK: - Navigate helpers

    /// `navigateToDeepClean()` raises the sheet so ``RootView`` can present
    /// ``DeepCleanView`` from a top-level toolbar tap.
    func testNavigateToDeepCleanRaisesFlag() {
        let coordinator = AppCoordinator(defaults: defaults)
        coordinator.navigateToDeepClean()
        XCTAssertTrue(coordinator.showDeepClean)
    }

    /// `navigateToStartupItems()` raises the sheet so ``RootView`` can
    /// present ``StartupItemsView`` from a top-level toolbar tap.
    func testNavigateToStartupItemsRaisesFlag() {
        let coordinator = AppCoordinator(defaults: defaults)
        coordinator.navigateToStartupItems()
        XCTAssertTrue(coordinator.showStartupItems)
    }

    // MARK: - Isolation between flags

    /// Toggling the DeepClean flag must not also raise the StartupItems
    /// sheet (and vice versa). The two entries are independent surfaces so
    /// the coordinator must not cross-wire them.
    func testDeepCleanAndStartupFlagsAreIndependent() {
        let coordinator = AppCoordinator(defaults: defaults)

        coordinator.navigateToDeepClean()
        XCTAssertTrue(coordinator.showDeepClean)
        XCTAssertFalse(coordinator.showStartupItems)

        coordinator.showDeepClean = false
        coordinator.navigateToStartupItems()
        XCTAssertFalse(coordinator.showDeepClean)
        XCTAssertTrue(coordinator.showStartupItems)
    }
}