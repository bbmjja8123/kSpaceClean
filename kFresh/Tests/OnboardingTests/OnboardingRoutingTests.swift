import XCTest
@testable import kFresh

@MainActor
final class OnboardingRoutingTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "OnboardingRoutingTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testFirstLaunchShowsOnboarding() {
        let coordinator = AppCoordinator(defaults: defaults)
        XCTAssertTrue(coordinator.showOnboarding)
    }

    func testReturningUserSkipsOnboarding() {
        defaults.set(true, forKey: FDAGuideController.onboardingKey)
        let coordinator = AppCoordinator(defaults: defaults)
        XCTAssertFalse(coordinator.showOnboarding)
    }

    func testOnboardingFinishedDismissesFlow() {
        let coordinator = AppCoordinator(defaults: defaults)
        XCTAssertTrue(coordinator.showOnboarding)
        coordinator.onboardingFinished()
        XCTAssertFalse(coordinator.showOnboarding)
    }

    /// The coordinator must hand its own defaults to the controller, otherwise
    /// completion would be written somewhere the next launch never reads.
    func testControllerCompletionIsVisibleToNextLaunch() {
        let coordinator = AppCoordinator(defaults: defaults)
        let controller = coordinator.makeOnboardingController()
        controller.markCompleted()

        let relaunched = AppCoordinator(defaults: defaults)
        XCTAssertFalse(relaunched.showOnboarding)
    }

    func testFreshControllerStartsAtWelcomeOnFirstLaunch() {
        let coordinator = AppCoordinator(defaults: defaults)
        let controller = coordinator.makeOnboardingController()
        XCTAssertEqual(controller.currentPage, .welcome)
        XCTAssertFalse(controller.isCompleted)
    }
}
