// kWise/Tests/LaunchEntitlementAndPaywallSuccessTests.swift
//
// P1 T7 fix r1 — locks two conversion/trust-critical behaviors:
//   1. Launch-time entitlement refresh: a purchased user who relaunches the
//      app must not be refused and shown the paywall (the retired quota
//      closure used to self-heal stale state before every cleanup; its
//      replacement is one refresh per launch, wired in AppGraph.init).
//   2. Paywall purchase success: a confirmed buyout must flip the sheet to
//      the unlocked row and auto-dismiss — the sheet is the only
//      conversion surface, so a dead-end is a bug.
//
// All seams are injectable closures / fakes — no StoreKit or network calls.
import XCTest
@testable import kWise

@MainActor
final class LaunchEntitlementRefreshTests: XCTestCase {

    /// Minimal StoreProtocol fake recording checkSubscription calls.
    private final class FakeStore: StoreProtocol, @unchecked Sendable {
        var hasPurchased = false
        private(set) var refreshCount = 0
        func checkSubscription() async { refreshCount += 1 }
        func purchase() async {}
        func restorePurchases() async {}
    }

    // MARK: StoreManager entitlement seam

    func testCheckSubscriptionGrantsOwnershipFromEntitlementSeam() async {
        let manager = StoreManager(entitlements: { [StoreManager.productID] })
        XCTAssertFalse(manager.hasPurchased)
        await manager.checkSubscription()
        XCTAssertTrue(manager.hasPurchased)
    }

    func testCheckSubscriptionDeniesWhenEntitlementAbsent() async {
        let manager = StoreManager(entitlements: { ["some.other.product"] })
        await manager.checkSubscription()
        XCTAssertFalse(manager.hasPurchased, "Only the buyout productID grants ownership")
    }

    func testCheckSubscriptionDeniesWhenNoEntitlements() async {
        // e.g. a purchased user's entitlements not yet visible — refresh
        // must land on the free tier, never on a stale true.
        let manager = StoreManager(entitlements: { [] })
        manager.hasPurchased = true
        await manager.checkSubscription()
        XCTAssertFalse(manager.hasPurchased)
    }

    // MARK: Launch refresh wiring

    /// The extracted launch hook goes through `checkSubscription()`.
    func testLaunchRefreshHookReentitlementsViaCheckSubscription() async {
        let store = FakeStore()
        await AppGraph.refreshEntitlementsAtLaunch(store)
        XCTAssertEqual(store.refreshCount, 1)
    }

    /// Locks the call site: AppGraph.init must fire the launch refresh
    /// (source-scan audit — same idiom as the copy audits; constructing the
    /// full graph in tests would pull the shared Core Data stack).
    func testAppGraphInitFiresLaunchRefresh() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // kWise/
        let source = try String(contentsOf:
            root.appendingPathComponent("App/AppGraph.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("Task { await Self.refreshEntitlementsAtLaunch(storeManager) }"),
                      "AppGraph.init must fire the per-launch entitlement refresh")
    }
}

@MainActor
final class PaywallSuccessModelTests: XCTestCase {

    func testPurchaseConfirmedFlipsToUnlocked() {
        let model = PaywallSuccessModel()
        XCTAssertFalse(model.unlocked)
        model.purchaseConfirmed()
        XCTAssertTrue(model.unlocked)
    }

    /// The auto-dismiss must wait long enough for the user to see the
    /// unlocked row (a zero delay would dismiss before any feedback).
    func testDismissDelayIsVisible() {
        XCTAssertGreaterThan(PaywallSuccessModel.dismissDelayNanoseconds, 300_000_000)
    }

    /// Locks the view wiring: success is driven by observing
    /// `store.hasPurchased` and ends in an automatic dismiss (source-scan
    /// audit — the sheet's dismissal cannot be driven in a unit test).
    func testPaywallViewObservesOwnershipAndAutoDismisses() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // kWise/
        let source = try String(contentsOf:
            root.appendingPathComponent("Store/PaywallView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains(".onChange(of: store.hasPurchased)"),
                      "PaywallView must observe ownership to enter the success state")
        XCTAssertTrue(source.contains("success.purchaseConfirmed()"),
                      "Ownership flip must route through the testable success model")
        XCTAssertTrue(source.contains("dismiss()"),
                      "The paywall must dismiss itself after a confirmed purchase")
    }
}
