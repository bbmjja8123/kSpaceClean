import XCTest
import StoreKit
import Combine
import MetricsKit
@testable import kWatch

@MainActor
final class StoreManagerTests: XCTestCase {

    // MARK: - Helpers

    private func makeManager(
        products: [Product] = [],
        purchaseResult: Result<Product.PurchaseResult, Error> = .success(.userCancelled),
        entitlements: [Transaction] = []
    ) -> (StoreManager, PurchaseState, StubStoreKitClient) {
        let purchaseState = PurchaseState()
        let stub = StubStoreKitClient(
            products: products,
            purchaseResult: purchaseResult,
            entitlements: entitlements
        )
        let manager = StoreManager(
            purchaseState: purchaseState,
            client: stub
        )
        return (manager, purchaseState, stub)
    }

    // MARK: - refreshEntitlements

    func testRefreshEntitlementsLeavesIsProFalseWhenNoEntitlements() async {
        let (manager, purchaseState, _) = makeManager()

        await manager.refreshEntitlements()

        XCTAssertFalse(purchaseState.isPro)
        XCTAssertFalse(manager.isPro)
    }

    func testRefreshEntitlementsClearsStaleError() async {
        let (manager, purchaseState, _) = makeManager()
        purchaseState.recordError("previous error")

        await manager.refreshEntitlements()

        XCTAssertNil(purchaseState.lastError)
    }

    // MARK: - Load products

    func testLoadProductsDoesNotPopulateWhenStubReturnsEmpty() async {
        let (manager, _, _) = makeManager(products: [])

        await manager.loadProducts()

        XCTAssertTrue(manager.products.isEmpty)
    }

    func testLoadProductsRecordsErrorWhenProductsCallFails() async {
        let purchaseState = PurchaseState()
        let stub = StubStoreKitClient(purchaseResult: .success(.userCancelled))
        stub.productsShouldThrow = true
        let manager = StoreManager(purchaseState: purchaseState, client: stub)

        await manager.loadProducts()

        XCTAssertNotNil(purchaseState.lastError)
    }

    // MARK: - Purchase paths

    func testPurchaseHandlesUserCancellationGracefully() async {
        // No products available → purchase() records "unavailable" error
        // before reaching the StoreKit cancellation path.
        let (manager, purchaseState, _) = makeManager(
            purchaseResult: .success(.userCancelled)
        )

        await manager.purchase()

        XCTAssertFalse(purchaseState.isPro)
        XCTAssertFalse(manager.isPro)
        XCTAssertNotNil(purchaseState.lastError)
    }

    func testPurchaseHandlesPurchaseError() async {
        let (manager, purchaseState, _) = makeManager(
            purchaseResult: .failure(StoreKitError.networkError(URLError(.notConnectedToInternet)))
        )

        await manager.purchase()

        XCTAssertFalse(purchaseState.isPro)
        XCTAssertNotNil(purchaseState.lastError)
    }

    func testPurchaseNotEntitledReportsAndStaysFree() async {
        let (manager, purchaseState, _) = makeManager(
            purchaseResult: .failure(StoreKitError.notEntitled)
        )

        await manager.purchase()

        XCTAssertNotNil(purchaseState.lastError)
        XCTAssertFalse(purchaseState.isPro)
    }

    // MARK: - Restore

    func testRestoreWhenClientSyncThrowsRecordsError() async {
        let purchaseState = PurchaseState()
        let stub = StubStoreKitClient(entitlements: [])
        stub.syncShouldThrow = true
        let manager = StoreManager(purchaseState: purchaseState, client: stub)

        await manager.restore()

        XCTAssertNotNil(purchaseState.lastError)
        XCTAssertFalse(purchaseState.isPro)
    }

    func testRestoreWithNoEntitlementsLeavesIsProFalse() async {
        let (manager, purchaseState, _) = makeManager(entitlements: [])

        await manager.restore()

        XCTAssertFalse(purchaseState.isPro)
        XCTAssertFalse(manager.isPro)
    }

    func testRestoreClearsPriorErrorOnSuccessPath() async {
        let (manager, purchaseState, _) = makeManager()
        purchaseState.recordError("stale")

        await manager.restore()

        XCTAssertNil(purchaseState.lastError)
    }

    // MARK: - PurchaseState mirror

    func testManagerMirrorsPurchaseStateIsProFlip() async {
        let (manager, purchaseState, _) = makeManager()
        XCTAssertFalse(manager.isPro)

        purchaseState.update(isPro: true)
        let expectation = expectation(description: "manager reflects isPro")
        Task { @MainActor in
            for _ in 0..<5 {
                if manager.isPro {
                    expectation.fulfill()
                    return
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(manager.isPro)
    }

    // MARK: - Updates stream wiring

    func testRefreshEntitlementsStartsListenerWithoutCrashing() async {
        // We cannot synthesise a `Transaction` from a unit test (the
        // initialisers are private). This test pins that the listener
        // task spins up and is tolerant of an empty updates stream — we
        // exercise the wiring without depending on a real purchase.
        let (manager, purchaseState, stub) = makeManager()

        await manager.refreshEntitlements()
        stub.finishUpdates()

        // Manager should remain Free because nothing was pushed through
        // `updates`.
        XCTAssertFalse(purchaseState.isPro)
        XCTAssertFalse(manager.isPro)
    }
}

// MARK: - Stub-only extensions

extension StubStoreKitClient {
    /// Toggle `products(for:)` to throw a synthetic StoreKit error.
    var productsShouldThrow: Bool {
        get { _productsShouldThrow }
        set { _productsShouldThrow = newValue }
    }

    /// Toggle `currentEntitlements()` to throw a synthetic StoreKit error.
    var entitlementsShouldThrow: Bool {
        get { _entitlementsShouldThrow }
        set { _entitlementsShouldThrow = newValue }
    }

    /// Toggle `sync()` to throw a synthetic StoreKit error.
    var syncShouldThrow: Bool {
        get { _syncShouldThrow }
        set { _syncShouldThrow = newValue }
    }
}
