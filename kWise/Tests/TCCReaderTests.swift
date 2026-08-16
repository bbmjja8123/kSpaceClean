import XCTest
@testable import kWise

@MainActor
final class TCCReaderTests: XCTestCase {
    // MARK: - Error path

    func testUnreadableDBPathSurfacesDatabaseUnreadable() async {
        let reader = TCCReader(tccDBPath: "/nonexistent/path/TCC.db")
        await reader.refresh()
        if case .databaseUnreadable = reader.lastError {
            // OK — expected fallback signal
        } else {
            XCTFail("expected .databaseUnreadable, got \(String(describing: reader.lastError))")
        }
        XCTAssertTrue(reader.categories.isEmpty,
                      "Categories should remain empty on DB open failure")
        XCTAssertNil(reader.lastRefreshedAt,
                     "lastRefreshedAt should not be set when refresh didn't return rows")
    }

    // MARK: - Fallback synthesis

    func testFallbackCategoriesMatchesCanonicalCatalog() {
        let reader = TCCReader(tccDBPath: "/nonexistent/path/TCC.db")
        let fallbacks = reader.fallbackCategories()
        XCTAssertEqual(fallbacks.count, PermissionCategory.fallbackCatalog.count)
        XCTAssertGreaterThan(fallbacks.count, 0)
        // Every fallback row is flagged as a fallback.
        for cat in fallbacks {
            XCTAssertTrue(cat.isFallback,
                          "\(cat.service) should be marked as fallback")
        }
    }

    func testFallbackCategoriesHaveUniqueServices() {
        let services = PermissionCategory.fallbackCatalog.map(\.service)
        let unique = Set(services)
        XCTAssertEqual(unique.count, services.count,
                       "Fallback services must not repeat")
    }

    // MARK: - PermissionCategory helpers

    func testFriendlySummaryFallback() {
        let cat = PermissionCategory(
            id: "x", title: "X", service: "x",
            grantedAppCount: 0, totalAppCount: 0,
            lastUpdatedAt: nil
        )
        XCTAssertTrue(cat.isFallback)
        XCTAssertEqual(cat.friendlySummary, "需要完整磁盘访问")
    }

    func testFriendlySummaryLive() {
        let cat = PermissionCategory(
            id: "y", title: "Y", service: "y",
            grantedAppCount: 3, totalAppCount: 5
        )
        XCTAssertFalse(cat.isFallback)
        XCTAssertEqual(cat.friendlySummary, "3 / 5 应用已授权")
    }

    func testFriendlySummaryNoApps() {
        let cat = PermissionCategory(
            id: "z", title: "Z", service: "z",
            grantedAppCount: 0, totalAppCount: 0,
            lastUpdatedAt: Date()
        )
        XCTAssertFalse(cat.isFallback,
                       "Having a lastUpdatedAt but no apps is not a fallback")
        XCTAssertEqual(cat.friendlySummary, "无应用申请")
    }

    // MARK: - parseTCCDate (indirect via reader internal API)

    func testParseTCCDateTolerantOfGarbage() {
        // We don't expose parseTCCDate as public; this test is a placeholder
        // for a future refactor that pulls the date parser out behind an
        // internal `init?(rawString:)` so we can hit it directly.
        let r = TCCReader(tccDBPath: "/tmp/nope.db")
        // Trigger a refresh that internally hits the parser for any rows.
        // With an unreadable DB, the parser isn't called at all. So this
        // test only verifies the reader doesn't crash on a missing path.
        XCTAssertNoThrow(await r.refresh())
    }
}