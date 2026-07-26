import XCTest
import MetricsKit
@testable import kWatch

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    func testOnboardingFlowAdvancesAndCompletes() {
        let prefs = InMemoryPreferences()
        let model = OnboardingViewModel(preferences: prefs)
        XCTAssertEqual(model.page, .welcome)
        model.next()
        XCTAssertEqual(model.page, .customize)
        model.next()
        XCTAssertEqual(model.page, .proIntro)
        model.next()
        XCTAssertEqual(model.page, .complete)
        XCTAssertFalse(prefs.onboardingCompleted)
        model.complete()
        XCTAssertTrue(prefs.onboardingCompleted)
        XCTAssertEqual(model.page, .complete)
    }

    func testOnboardingCanGoBackFromCustomize() {
        let prefs = InMemoryPreferences()
        let model = OnboardingViewModel(preferences: prefs)
        model.next()
        XCTAssertEqual(model.page, .customize)
        XCTAssertTrue(model.canGoBack)
        model.back()
        XCTAssertEqual(model.page, .welcome)
    }

    func testSkipOnlyAppliesToProIntro() {
        let prefs = InMemoryPreferences()
        let model = OnboardingViewModel(preferences: prefs)
        model.skip()
        XCTAssertEqual(model.page, .welcome)
        model.next(); model.next()
        XCTAssertEqual(model.page, .proIntro)
        model.skip()
        XCTAssertEqual(model.page, .complete)
    }

    func testCompletePersistsSelections() {
        let prefs = InMemoryPreferences()
        let model = OnboardingViewModel(preferences: prefs)
        model.selectedMode = .minimal
        model.enabledKinds = [.cpu]
        model.complete()
        XCTAssertEqual(prefs.menuBarMode, .minimal)
        XCTAssertEqual(prefs.enabledKinds, [.cpu])
        XCTAssertTrue(prefs.onboardingCompleted)
    }
}