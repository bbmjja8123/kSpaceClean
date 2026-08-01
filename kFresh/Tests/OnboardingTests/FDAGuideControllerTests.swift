import XCTest
@testable import kFresh

@MainActor
final class FDAGuideControllerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "FDAGuideControllerTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    private func makeController() -> FDAGuideController {
        FDAGuideController(probe: FDAPermissionProbe(protectedPaths: []), defaults: defaults)
    }

    // MARK: - Initial state

    func testStartsAtWelcome() {
        let controller = makeController()
        XCTAssertEqual(controller.currentPage, .welcome)
        XCTAssertFalse(controller.isCompleted)
        XCTAssertEqual(controller.fdaStatus, .unknown)
    }

    func testPageOrderMatchesMandatedOnboardingSkeleton() {
        // CLAUDE.md §5.4: Welcome → 价值主张 → 权限申请 → 隐私承诺 → Ready
        XCTAssertEqual(
            FDAGuideController.Page.allCases,
            [.welcome, .value, .permission, .privacy, .ready]
        )
    }

    // MARK: - Navigation

    func testAdvanceProgressesThroughPages() {
        let controller = makeController()
        controller.advance()
        XCTAssertEqual(controller.currentPage, .value)
        controller.advance()
        XCTAssertEqual(controller.currentPage, .permission)
        controller.advance()
        XCTAssertEqual(controller.currentPage, .privacy)
        controller.advance()
        XCTAssertEqual(controller.currentPage, .ready)
        XCTAssertFalse(controller.isCompleted, "reaching .ready must not finish onboarding on its own")
        controller.advance()
        XCTAssertTrue(controller.isCompleted)
    }

    func testAdvanceBeyondReadyStaysOnReady() {
        let controller = makeController()
        for _ in 0..<10 { controller.advance() }
        XCTAssertEqual(controller.currentPage, .ready)
        XCTAssertTrue(controller.isCompleted)
    }

    func testSkipFromPermissionJumpsToReady() {
        let controller = makeController()
        controller.advance()  // value
        controller.advance()  // permission
        XCTAssertEqual(controller.currentPage, .permission)
        controller.skipFromPermission()
        XCTAssertEqual(controller.currentPage, .ready)
        XCTAssertFalse(controller.isCompleted, "skipping permission must not finish onboarding")
    }

    // MARK: - Persistence

    func testMarkCompletedPersistsToDefaults() {
        let controller = makeController()
        controller.markCompleted()
        XCTAssertTrue(defaults.bool(forKey: FDAGuideController.onboardingKey))
        XCTAssertTrue(controller.isCompleted)
    }

    func testCompletionKeyIsNamespacedToKFresh() {
        XCTAssertEqual(FDAGuideController.onboardingKey, "kFresh.hasCompletedOnboarding")
    }

    func testCompletionIsObservableForRouting() {
        // RootView dismisses the sheet by observing this published flag, so it
        // must change rather than only being written through to UserDefaults.
        let controller = makeController()
        XCTAssertFalse(controller.isCompleted)
        controller.markCompleted()
        XCTAssertTrue(controller.isCompleted)
    }

    func testReturningUserStartsCompleted() {
        defaults.set(true, forKey: FDAGuideController.onboardingKey)
        let controller = makeController()
        XCTAssertTrue(controller.isCompleted)
    }

    // MARK: - FDA status

    func testRefreshFDAStatusPublishesProbeResult() async {
        let controller = makeController()  // probe has no readable protected paths
        await controller.refreshFDAStatus()
        XCTAssertEqual(controller.fdaStatus, .basic)
    }

    func testRefreshFDAStatusReportsFullWhenAccessible() async {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
        let controller = FDAGuideController(
            probe: FDAPermissionProbe(protectedPaths: [temp]),
            defaults: defaults
        )
        await controller.refreshFDAStatus()
        XCTAssertEqual(controller.fdaStatus, .full)
    }
}
