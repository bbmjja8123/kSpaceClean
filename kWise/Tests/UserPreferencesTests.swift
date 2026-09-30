import XCTest
@testable import kWise

final class UserPreferencesTests: XCTestCase {
    func test_defaultValues() {
        let prefs = UserPreferences()
        XCTAssertEqual(prefs.largeFileThreshold, 100 * 1024 * 1024)
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
        prefs.defaultCleanAction = .permanent
        prefs.confirmHighRisk = false
        prefs.historyRetentionDays = 7
        prefs.launchAtLogin = true
        prefs.showMenuBarDiskUsage = false
        prefs.scanSpeed = .gentle
        prefs.ignoredPaths = ["/Library/Caches"]

        XCTAssertEqual(prefs.largeFileThreshold, 200 * 1024 * 1024)
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
        original.defaultCleanAction = .permanent
        original.scanSpeed = .gentle
        original.ignoredPaths = ["/tmp", "/Library"]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: data)

        XCTAssertEqual(decoded.largeFileThreshold, original.largeFileThreshold)
        XCTAssertEqual(decoded.defaultCleanAction, original.defaultCleanAction)
        XCTAssertEqual(decoded.scanSpeed, original.scanSpeed)
        XCTAssertEqual(decoded.ignoredPaths, original.ignoredPaths)
    }

    /// P1 T9 — `aiClassificationEnabled` / `assistantEnabled` 已随旧规则
    /// 引擎与助手门控删除。磁盘上仍存在这两个 key 的旧 JSON 必须能解码：
    /// Swift 合成解码忽略多余 key，非 Optional 字段缺省值兜底。
    func test_decodingLegacyJSONWithRetiredKeysIsBackwardCompatible() throws {
        let legacyJSON = """
        {
          "largeFileThreshold": 104857600,
          "ignoredPaths": [],
          "aiClassificationEnabled": false,
          "defaultCleanAction": "trash",
          "confirmHighRisk": true,
          "historyRetentionDays": 30,
          "launchAtLogin": false,
          "showMenuBarDiskUsage": true,
          "scanSpeed": "medium",
          "notifyAfterCleanup": false,
          "shredPasses": 1,
          "assistantEnabled": true
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: legacyJSON)
        XCTAssertEqual(decoded.largeFileThreshold, 100 * 1024 * 1024)
        XCTAssertEqual(decoded.defaultCleanAction, .trash)
        XCTAssertEqual(decoded.shredPasses, 1)
    }
}
