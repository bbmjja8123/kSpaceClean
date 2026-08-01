import XCTest
import StoreKit
import Combine
@testable import kWatch

@MainActor
final class PaywallViewModelTermsTests: XCTestCase {
    private func makeViewModel(isPro: Bool = false) -> (PaywallViewModel, StubStoreManager, PurchaseState) {
        let purchaseState = PurchaseState()
        let storeManager = StubStoreManager(
            productID: "app.kraftly.kwatch.pro",
            products: [],
            isPro: isPro,
            purchaseState: purchaseState
        )
        let viewModel = PaywallViewModel(storeManager: storeManager, purchaseState: purchaseState)
        return (viewModel, storeManager, purchaseState)
    }

    func testAcceptedTermsDefaultsToFalse() {
        let (viewModel, _, _) = makeViewModel()
        XCTAssertFalse(viewModel.acceptedTerms)
    }

    func testAcknowledgeTermsFlipsAcceptedTermsTrue() {
        let (viewModel, _, _) = makeViewModel()
        viewModel.acknowledgeTerms()
        XCTAssertTrue(viewModel.acceptedTerms)
    }

    func testCanPurchaseIsFalseUntilTermsAccepted() {
        let (viewModel, _, _) = makeViewModel()
        XCTAssertFalse(viewModel.canPurchase)

        viewModel.acknowledgeTerms()
        XCTAssertTrue(viewModel.canPurchase)
    }

    func testCanPurchaseIgnoresAcceptanceForProUsers() {
        // Pro users see the paywall rarely; they should be able to re-purchase
        // (e.g. gift) without re-accepting terms on every visit.
        let (viewModel, _, _) = makeViewModel(isPro: true)
        XCTAssertTrue(viewModel.canPurchase)
    }
}