import XCTest
@testable import kFresh

/// Placeholder UI test for the first-launch onboarding flow.
///
/// The full journey test (walking the five pages, exercising the FDA badge,
/// skipping to Ready) lands in a later Wave 1 task. Today this bundle has no
/// UI test target — it is a unit bundle hosted inside kFresh.app, so
/// `XCUIApplication()` cannot launch without a `targetApplicationPath` in the
/// test configuration. Until a dedicated UI test target exists, this class
/// guards the CLAUDE.md §5.4 onboarding skeleton (exactly five pages, in the
/// mandated order) through the controller API instead.
final class OnboardingUITests: XCTestCase {
    func testOnboardingHasFivePageContract() {
        let pages = FDAGuideController.Page.allCases
        XCTAssertEqual(pages.map(\.rawValue), [0, 1, 2, 3, 4])
        XCTAssertEqual(pages.count, 5)
    }

    func testPageOrderMatchesBrandSkeleton() {
        let order = FDAGuideController.Page.allCases
        XCTAssertEqual(order[0], .welcome)
        XCTAssertEqual(order[1], .value)
        XCTAssertEqual(order[2], .permission)
        XCTAssertEqual(order[3], .privacy)
        XCTAssertEqual(order[4], .ready)
    }
}
