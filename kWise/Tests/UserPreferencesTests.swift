import XCTest
@testable import kWise

final class UserPreferencesTests: XCTestCase {
    func test_defaultValues() {
        let prefs = UserPreferences()
        XCTAssertEqual(prefs.largeFileThreshold, 100 * 1024 * 1024)
        XCTAssertTrue(prefs.aiClassificationEnabled)
        XCTAssertEqual(prefs.defaultCleanAction, .trash)
        XCTAssertTrue(prefs.confirmHighRisk)
        XCTAssertEqual(prefs.historyRetentionDays, 30)
        XCTAssertFalse(prefs.launchAtLogin)
        XCTAssertTrue(prefs.showMenuBarDiskUsage)
        XCTAssertEqual(prefs.scanSpeed, .medium)
    }

    func test_customValues() {
        var prefs = UserPreferences()
        prefs.largeFileThreshold = 200 * 1024 * 1024
        prefs.aiClassificationEnabled = false
        prefs.defaultCleanAction = .permanent
        prefs.confirmHighRisk = false
        prefs.historyRetentionDays = 7
        prefs.launchAtLogin = true
        prefs.showMenuBarDiskUsage = false
        prefs.scanSpeed = .gentle
        prefs.ignoredPaths = ["/Library/Caches"]

        XCTAssertEqual(prefs.largeFileThreshold, 200 * 1024 * 1024)
        XCTAssertFalse(prefs.aiClassificationEnabled)
        XCTAssertEqual(prefs.defaultCleanAction, .permanent)
        XCTAssertFalse(prefs.confirmHighRisk)
        XCTAssertEqual(prefs.historyRetentionDays, 7)
        XCTAssertTrue(prefs.launchAtLogin)
        XCTAssertFalse(prefs.showMenuBarDiskUsage)
        XCTAssertEqual(prefs.scanSpeed, .gentle)
        XCTAssertEqual(prefs.ignoredPaths, ["/Library/Caches"])
    }

    func test_codable_roundTrip() throws {
        var original = UserPreferences()
        original.largeFileThreshold = 500 * 1024 * 1024
        original.aiClassificationEnabled = false
        original.defaultCleanAction = .permanent
        original.scanSpeed = .gentle
        original.ignoredPaths = ["/tmp", "/Library"]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: data)

        XCTAssertEqual(decoded.largeFileThreshold, original.largeFileThreshold)
        XCTAssertEqual(decoded.aiClassificationEnabled, original.aiClassificationEnabled)
        XCTAssertEqual(decoded.defaultCleanAction, original.defaultCleanAction)
        XCTAssertEqual(decoded.scanSpeed, original.scanSpeed)
        XCTAssertEqual(decoded.ignoredPaths, original.ignoredPaths)
    }
}
