import Foundation
import SwiftUI
import Combine
import StoreKit

/// `@MainActor` view-model that drives `PaywallView`. Owns the underlying
/// `StoreManager` reference, surfaces a localized price line, and forwards
/// the user's intents (`purchase`, `restore`, `dismiss`) to the manager.
@MainActor
public final class PaywallViewModel: ObservableObject {
    /// Pricing copy built from the loaded `Product`. Falls back to a
    /// static string while the product list is loading or when StoreKit
    /// returns an unexpected response.
    @Published public private(set) var priceLine: String = "$7.99"

    /// Whether a purchase is currently in flight. Drives the spinner on
    /// `PurchaseButton`.
    @Published public private(set) var isPurchasing: Bool = false

    /// Whether a restore is currently in flight. Drives the spinner on the
    /// Restore Purchases link.
    @Published public private(set) var isRestoring: Bool = false

    /// The current Pro status, mirrored from the store manager. View code
    /// reads this when deciding whether to show the "Already Pro" footer.
    @Published public private(set) var isPro: Bool

    /// Surface error from `PurchaseState`. The view listens and shows a
    /// localized banner.
    @Published public private(set) var errorMessage: String?

    /// Whether the user has acknowledged the auto-renewal disclosure.
    /// Defaults to `false`; the paywall disables the purchase button
    /// until the user checks the terms checkbox (or is already Pro).
    @Published public var acceptedTerms: Bool = false

    /// Convenience flag combining `isPro` (Pro users can re-purchase
    /// without re-accepting) and `acceptedTerms` for free-tier users.
    public var canPurchase: Bool {
        isPro || acceptedTerms
    }

    /// Set when the user successfully completes a purchase so the view can
    /// dismiss itself.
    @Published public private(set) var didCompletePurchase: Bool = false

    private let storeManager: any StoreManagerProtocol
    private let purchaseState: PurchaseState
    private var cancellables: Set<AnyCancellable> = []

    public init(storeManager: any StoreManagerProtocol, purchaseState: PurchaseState) {
        self.storeManager = storeManager
        self.purchaseState = purchaseState
        self.isPro = storeManager.isPro
        bind()
    }

    // MARK: - Intents

    /// Refresh the product list and the cached price string. Called when
    /// the paywall appears.
    public func refresh() async {
        await storeManager.loadProducts()
        await storeManager.refreshEntitlements()
        applyPriceLine()
        isPro = storeManager.isPro
    }

    /// Buy `app.kraftly.kwatch.pro`. Triggers the in-flight spinner on
    /// `PurchaseButton` and surfaces errors through `errorMessage`.
    public func purchase() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        await storeManager.purchase()
        applyPriceLine()
        isPro = storeManager.isPro
        if storeManager.isPro {
            didCompletePurchase = true
        }
    }

    /// Restore previous purchases. Refreshes the Pro flag at the end.
    public func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        await storeManager.restore()
        isPro = storeManager.isPro
        if storeManager.isPro {
            didCompletePurchase = true
        }
    }

    /// Clear the most recent error so the inline banner disappears.
    public func clearError() {
        purchaseState.clearError()
        errorMessage = nil
    }

    /// Flip `acceptedTerms` to `true`. Called from the paywall checkbox.
    public func acknowledgeTerms() {
        acceptedTerms = true
    }

    // MARK: - Internals

    private func bind() {
        // Mirror published state from the store manager so the view can
        // observe price, Pro status, and the completion flag without
        // reaching into the manager directly.
        storeManager.productsPublisher
            .sink { [weak self] _ in
                self?.applyPriceLine()
            }
            .store(in: &cancellables)

        storeManager.isProPublisher
            .sink { [weak self] value in
                guard let self else { return }
                self.isPro = value
                if value {
                    self.didCompletePurchase = true
                }
            }
            .store(in: &cancellables)

        purchaseState.$lastError
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.errorMessage = message
            }
            .store(in: &cancellables)
    }

    private func applyPriceLine() {
        guard let product = storeManager.primaryProduct else {
            // Localised price unavailable — fall back to the configured
            // reference price. Region-specific copy is filled in by the
            // real `Product.displayPrice` once StoreKit returns.
            priceLine = "$7.99"
            return
        }
        priceLine = "\(product.displayPrice) — one-time purchase"
    }
}

// MARK: - Combine bridging

extension StoreManagerProtocol {
    /// Combine publisher for `products`. Provided so view models can
    /// subscribe via Combine even though the protocol exposes raw values.
    var productsPublisher: AnyPublisher<[Product], Never> {
        if let publisher = self as? StoreManager {
            return publisher.$products.eraseToAnyPublisher()
        }
        if let publisher = self as? StubStoreManager {
            return publisher.$products.eraseToAnyPublisher()
        }
        return Empty(completeImmediately: true).eraseToAnyPublisher()
    }

    /// Combine publisher for `isPro`. Mirrors `productsPublisher` for the
    /// Pro flag.
    var isProPublisher: AnyPublisher<Bool, Never> {
        if let publisher = self as? StoreManager {
            return publisher.$isPro.eraseToAnyPublisher()
        }
        if let publisher = self as? StubStoreManager {
            return publisher.$isPro.eraseToAnyPublisher()
        }
        return Empty(completeImmediately: true).eraseToAnyPublisher()
    }
}
