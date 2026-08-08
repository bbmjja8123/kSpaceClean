import XCTest
@testable import kSift

/// Pure-function tests for the free-tier quota gate. The static helper is
/// kept side-effect-free so it can be exercised without a StoreKit
/// entitlement, App Store sandbox, or `UserDefaults` mutation.
final class StoreManagerTests: XCTestCase {
    /// Free-tier cap is exactly 2 GB per spec §1.4 — locked here so the
    /// accidental change is caught at test time.
    func testQuotaConstantIs2GB() {
        XCTAssertEqual(
            StoreManager.freeCleanupQuotaBytes,
            Int64(2) * 1024 * 1024 * 1024,
            "freeCleanupQuotaBytes must remain 2 GB per spec §1.4"
        )
    }

    /// Paid users always pass regardless of bytes — the quota is meaningless
    /// once Pro is unlocked.
    func testPaidUserBypassesQuota() {
        XCTAssertTrue(StoreManager.canCleanup(cleanedSoFar: 100_000_000_000,
                                             additionalBytes: 50_000_000_000,
                                             isPaid: true))
        XCTAssertTrue(StoreManager.canCleanup(cleanedSoFar: 0,
                                             additionalBytes: Int64.max,
                                             isPaid: true))
    }

    /// Free users below the cap are allowed.
    func testFreeUserUnderCapAllowed() {
        XCTAssertTrue(StoreManager.canCleanup(
            cleanedSoFar: 0,
            additionalBytes: StoreManager.freeCleanupQuotaBytes - 1,
            isPaid: false
        ))
    }

    /// Free user at exactly the cap is still allowed — the limit is inclusive.
    func testFreeUserAtExactCapAllowed() {
        XCTAssertTrue(StoreManager.canCleanup(
            cleanedSoFar: 0,
            additionalBytes: StoreManager.freeCleanupQuotaBytes,
            isPaid: false
        ))
    }

    /// Free user over the cap is rejected — this is the gate the paywall
    /// flows (Delete, Trash, cleanup intents) check before showing the
    /// upgrade sheet.
    func testFreeUserOverCapBlocked() {
        XCTAssertFalse(StoreManager.canCleanup(
            cleanedSoFar: 0,
            additionalBytes: StoreManager.freeCleanupQuotaBytes + 1,
            isPaid: false
        ))
    }

    /// Accumulated usage + new request must still respect the cap. Covers
    /// the realistic case of a user who cleaned some bytes last week.
    func testFreeUserAccumulatedUsageEnforced() {
        let alreadyCleaned = StoreManager.freeCleanupQuotaBytes - 100
        XCTAssertTrue(StoreManager.canCleanup(
            cleanedSoFar: alreadyCleaned,
            additionalBytes: 100,
            isPaid: false
        ))
        XCTAssertFalse(StoreManager.canCleanup(
            cleanedSoFar: alreadyCleaned,
            additionalBytes: 101,
            isPaid: false
        ))
    }
}