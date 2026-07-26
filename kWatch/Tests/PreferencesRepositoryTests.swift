import XCTest
@testable import kWatch

final class PreferencesRepositoryTests: XCTestCase {
    func testInMemoryPreferencesDefaultToFreeMetricsAndTrend() {
        let preferences = InMemoryPreferences()

        XCTAssertEqual(preferences.menuBarMode, .trend)
        XCTAssertTrue(preferences.enabledKinds.contains(.cpu))
        XCTAssertTrue(preferences.enabledKinds.contains(.memory))
        XCTAssertTrue(preferences.enabledKinds.contains(.disk))
        XCTAssertTrue(preferences.enabledKinds.contains(.network))
        XCTAssertFalse(preferences.onboardingCompleted)
        XCTAssertEqual(preferences.samplingIntervalSeconds, 2.0, accuracy: 0.001)
    }

    func testPreferencesPersistThroughUserDefaultsSuite() {
        let suiteName = "kWatch.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = PreferencesRepository(defaults: defaults)
        preferences.menuBarMode = .minimal
        preferences.onboardingCompleted = true
        preferences.enabledKinds = [.cpu, .memory]

        let reread = PreferencesRepository(defaults: defaults)
        XCTAssertEqual(reread.menuBarMode, .minimal)
        XCTAssertTrue(reread.onboardingCompleted)
        XCTAssertEqual(reread.enabledKinds, [.cpu, .memory])
    }
}
