import XCTest
@testable import kWise

@MainActor
final class StoreManagerTests: XCTestCase {
    func test_storeManager_conformsToStoreProtocol() {
        let manager = StoreManager()
        XCTAssertTrue(manager is StoreProtocol)
    }

    func test_storeManager_initialState_unpurchased() {
        let manager = StoreManager()
        XCTAssertFalse(manager.hasPurchased)
    }

    /// P1 T7 — the commerce model is a single $9.90 non-consumable buyout
    /// (`app.kraftly.klaris.buyout`), not the retired yearly subscription.
    func test_storeManager_productIDIsBuyoutNonConsumable() {
        XCTAssertEqual(StoreManager.productID, "app.kraftly.klaris.buyout")
    }

    /// Non-consumable purchase result handling — outcomes that do NOT
    /// establish ownership must leave `hasPurchased` false. (`Transaction`
    /// cannot be constructed in-process, so the verified-ownership branch is
    /// exercised by `checkEntitlements` against StoreKit's current
    /// entitlements in the .storekit simulator environment, not here.)
    func test_purchase_userCancelledDoesNotGrantOwnership() async {
        let manager = StoreManager()
        await manager.handlePurchaseResult(.userCancelled)
        XCTAssertFalse(manager.hasPurchased)
    }

    func test_purchase_pendingDoesNotGrantOwnership() async {
        let manager = StoreManager()
        await manager.handlePurchaseResult(.pending)
        XCTAssertFalse(manager.hasPurchased)
    }
}
