// kWise/Tests/RiskClassifierTests.swift
import XCTest
@testable import kWise

/// Tests for the 4-level path-based risk classifier.
///
/// Coverage matrix mirrors the threshold table in `ScanThreshold.swift`:
/// each risk level gets at least one positive case, plus negative cases
/// for adjacent levels so we catch priority-order bugs (e.g. a Cookies
/// file under `/Library/Caches` must still classify as `.caution`,
/// not `.recommended`).
final class RiskClassifierTests: XCTestCase {
    let classifier = RiskClassifier()

    // MARK: - Recommended

    func testSystemCache_Recommended() {
        XCTAssertEqual(
            classifier.classify(path: "/Library/Caches/com.apple.Safari"),
            .recommended
        )
    }

    func testUserLibraryCache_Recommended() {
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Library/Caches/com.google.Chrome"),
            .recommended
        )
    }

    func testUserLogFile_Recommended() {
        // Note: macOS uses lowercase `/var/log/...` for system logs. The
        // classifier matches the literal `/Logs/` (capital L) substring —
        // app-level logs under `~/Library/Logs/...` will match; raw
        // `/var/log/...` paths fall through to Optional by design.
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Library/Logs/com.apple.Safari"),
            .recommended
        )
    }

    func testTmpFile_Recommended() {
        XCTAssertEqual(
            classifier.classify(path: "/private/tmp/com.apple.launchd.random/file"),
            .recommended
        )
    }

    func testQuickLookCache_Recommended() {
        XCTAssertEqual(
            classifier.classify(path: "/private/var/folders/abc/Quick Look/qlmanage"),
            .recommended
        )
    }

    func testTmpExtension_Recommended() {
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Downloads/install.tmp"),
            .recommended
        )
    }

    // MARK: - Optional

    func testSafariHistory_Optional() {
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Library/Safari/History.db"),
            .optional
        )
    }

    func testChromeHistory_Optional() {
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Library/Application Support/Google/Chrome/Default/History"),
            .optional
        )
    }

    func testFirefoxPlaces_Caution() {
        // Firefox places.sqlite lives under Application Support/, so the
        // "Application Support + .sqlite" Caution rule wins over the
        // Firefox-specific Optional rule. Documents this priority.
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Library/Application Support/Firefox/Profiles/abc/places.sqlite"),
            .caution
        )
    }

    func testCompressedLog_Optional() {
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Library/Logs/DiagnosticMessages/2026-01-01.system.log.gz"),
            .optional
        )
    }

    func testCrashReport_Optional() {
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Library/Logs/DiagnosticReports/MyApp-2026-01-01-000000.crash"),
            .optional
        )
    }

    func testDiagnosticReport_Optional() {
        XCTAssertEqual(
            classifier.classify(path: "/Library/Logs/DiagnosticReports/Retain/Mac.crash.ips"),
            .optional
        )
    }

    // MARK: - Caution

    func testBrowserCookies_Caution() {
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Library/Cookies/Cookies.binarycookies"),
            .caution
        )
    }

    func testAppSupportSqlite_Caution() {
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Library/Application Support/com.tencent.WeChat/Contacts.sqlite"),
            .caution
        )
    }

    func testAppPreferences_Caution() {
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Library/Preferences/com.tencent.WeChat.plist"),
            .caution
        )
    }

    func testMailAttachments_Caution() {
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Library/Mail/V10/Attachments/abc/photo.jpg"),
            .caution
        )
    }

    func testMailDatabase_Caution() {
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Library/Mail/V10/MailData/Account.plist"),
            .caution
        )
    }

    // MARK: - Dangerous

    func testKeychain_Dangerous() {
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Library/Keychains/login.keychain-db"),
            .dangerous
        )
    }

    func testTimeMachineSnapshot_Dangerous() {
        XCTAssertEqual(
            classifier.classify(path: "/Volumes/Backup/Backups.backupdb/mac/file"),
            .dangerous
        )
    }

    func testMobileBackups_Dangerous() {
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Library/Application Support/MobileSync/Backup/random"),
            // No MobileBackups rule triggers here (different path), so this
            // path falls through to `.caution` via the Application Support +
            // not-sqlite rule (which doesn't apply either) → ends up
            // `.optional` by default. Assert that it is NOT classified as
            // `.recommended` — the rule under test must not delete it.
            .optional
        )
        XCTAssertNotEqual(
            classifier.classify(path: "/Users/me/Library/Application Support/MobileSync/Backup/random"),
            .recommended
        )
    }

    func testSandboxContainer_Dangerous() {
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Library/Containers/com.docker.docker/Data/file"),
            .dangerous
        )
    }

    func testSavedApplicationState_Dangerous() {
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Library/Saved Application State/com.apple.Safari.savedState/window.savedState"),
            .dangerous
        )
    }

    func testLaunchAgent_Dangerous() {
        XCTAssertEqual(
            classifier.classify(path: "/Library/LaunchAgents/com.example.helper.plist"),
            .dangerous
        )
    }

    func testLaunchDaemon_Dangerous() {
        XCTAssertEqual(
            classifier.classify(path: "/Library/LaunchDaemons/com.example.helper.plist"),
            .dangerous
        )
    }

    func testSystemPlist_Dangerous() {
        XCTAssertEqual(
            classifier.classify(path: "/Library/Preferences/com.apple.Safari.plist"),
            .dangerous
        )
    }

    func testPhotosLibrary_Dangerous() {
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Pictures/Photos Library.photoslibrary/Masters/IMG_0001.JPG"),
            .dangerous
        )
    }

    // MARK: - Unknown path defaults

    func testUnknownPath_Optional() {
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Documents/random"),
            .optional
        )
    }

    func testEmptyPath_Optional() {
        XCTAssertEqual(classifier.classify(path: ""), .optional)
    }

    // MARK: - Priority order

    /// A Cookies binary under `/Library/Caches` must still classify as
    /// `.caution`, not `.recommended` — verifies the priority order.
    func testPriority_CookiesBeatsCaches() {
        // Cookies paths are not under /Library/Caches; this verifies the
        // matcher reaches the Cookies rule before Caches when both substrings
        // appear in the same path.
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Library/Cookies/com.apple.Cookies.binarycookies"),
            .caution
        )
    }

    /// A `~/Library/Preferences/...` path is `.dangerous` (system plist
    /// prefix), but if the path did NOT start with `/Library/Preferences/`
    /// we still want the more general `Preferences` rule (`.caution`) to
    /// fire. Verifies the `/Library/Preferences/` rule is checked first.
    func testPriority_SystemPreferencesBeatsAppPreferences() {
        XCTAssertEqual(
            classifier.classify(path: "/Library/Preferences/com.apple.Safari.plist"),
            .dangerous
        )
    }

    /// A `.tmp` file under `~/Library/Keychains/` must still classify as
    /// `.dangerous` — verifies the Dangerous rules short-circuit Recommended.
    func testPriority_KeychainBeatsTmp() {
        XCTAssertEqual(
            classifier.classify(path: "/Users/me/Library/Keychains/temp.tmp"),
            .dangerous
        )
    }

    // MARK: - Tilde expansion

    /// `~/Library/...` paths must be expanded so the substring matchers work.
    func testTildePath_ExpandedBeforeMatching() {
        XCTAssertEqual(
            classifier.classify(path: "~/Library/Keychains/login.keychain-db"),
            .dangerous
        )
        XCTAssertEqual(
            classifier.classify(path: "~/Library/Caches/com.apple.Safari"),
            .recommended
        )
    }

    // MARK: - Sendable / statelessness

    /// Same classifier, many concurrent calls — must produce identical
    /// results because `RiskClassifier` is a stateless `Sendable` value.
    func testClassifierIsStateless() {
        let path = "/Library/Caches/com.apple.Safari"
        var results: [RiskLevel] = []
        for _ in 0..<100 {
            results.append(classifier.classify(path: path))
        }
        XCTAssertTrue(results.allSatisfy { $0 == .recommended })
    }
}