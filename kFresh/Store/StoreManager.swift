import Foundation
import StoreKit
import SwiftUI

/// Owns StoreKit 2 product loading, purchasing, restoration, and the
/// entitlement state that drives ``ProGateModifier`` and the app's Pro
/// feature gates.
///
/// The test override (see ``setProForTesting(_:)`` or the `-kFreshTestPro 1`
/// launch argument) is honored before real StoreKit entitlements, so UI tests
/// and previews can exercise both sides of the gate deterministically.
@MainActor
final class StoreManager: ObservableObject {
    /// UserDefaults key backing the Pro test override (see
    /// ``setProForTesting(_:)``).
    nonisolated static var testOverrideKey: String { kFreshTestProOverrideKey }

    @Published private(set) var state: ProState = .free
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseInProgress = false

    private var updatesTask: Task<Void, Never>?

    /// Creates the manager. The test override is read first; real
    /// entitlements are loaded by ``refresh()``.
    init() {
        if UserDefaults.standard.bool(forKey: kFreshTestProOverrideKey) {
            state = .pro
        }
        updatesTask = Task { [weak self] in
            await self?.listenForTransactionUpdates()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Loads product metadata and refreshes the entitlement state.
    ///
    /// A product-load failure leaves ``products`` empty — the paywall renders
    /// a retry affordance instead of an endless spinner. An entitlement error
    /// never clears a verified Pro state.
    func refresh() async {
        do {
            products = try await Product.products(for: StoreProduct.allCases.map(\.rawValue))
        } catch {
            products = []
        }
        await refreshEntitlements()
    }

    /// Purchases the given product, throwing ``StoreError`` on failure so call
    /// sites can surface localized feedback.
    func purchase(_ product: StoreProduct) async throws {
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        guard let storeProduct = products.first(where: { $0.id == product.rawValue }) else {
            throw StoreError.productNotFound
        }
        let result = try await storeProduct.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                state = .pro
            case .unverified:
                throw StoreError.verificationFailed
            }
        case .userCancelled:
            throw StoreError.userCancelled
        case .pending:
            throw StoreError.pending
        @unknown default:
            throw StoreError.unknown
        }
    }

    /// Restores previously purchased products, then refreshes entitlements.
    func restorePurchases() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }

    /// Test seam: forces Pro on/off by writing the shared override key.
    func setProForTesting(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: kFreshTestProOverrideKey)
        state = value ? .pro : .free
    }

    /// Parses the `-kFreshTestPro <0|1>` launch-argument pair used by the
    /// Pro-gate UI tests. Nonisolated so the app entry point can call it
    /// before any actor-isolated work begins.
    nonisolated static func parseTestProArgument(_ arguments: [String]) -> Bool {
        guard let index = arguments.firstIndex(of: "-kFreshTestPro"),
              arguments.indices.contains(index + 1),
              arguments[index + 1] == "1" else {
            return false
        }
        return true
    }

    /// Applies the `-kFreshTestPro <0|1>` launch-argument pair to the override
    /// key, unconditionally: a missing or `0` argument clears any stale `true`
    /// from a previous launch, so the override always reflects this launch.
    nonisolated static func applyTestProOverride(_ arguments: [String]) {
        UserDefaults.standard.set(
            parseTestProArgument(arguments),
            forKey: testOverrideKey
        )
    }

    /// Whether Pro is unlocked. Honors the test override first, then consults
    /// the StoreKit entitlement stream. Nonisolated so App Intents can gate
    /// features without holding a long-lived manager.
    nonisolated static func isProUnlocked() async -> Bool {
        if UserDefaults.standard.bool(forKey: kFreshTestProOverrideKey) {
            return true
        }
        return await scanCurrentEntitlements()
    }

    // MARK: - Private

    private func refreshEntitlements() async {
        let unlocked = await Self.scanCurrentEntitlements()
        // The test override takes precedence over real entitlements.
        if !UserDefaults.standard.bool(forKey: kFreshTestProOverrideKey) {
            state = unlocked ? .pro : .free
        }
    }

    /// Reads the StoreKit entitlement stream without holding a long-lived
    /// ``StoreManager``. Nonisolated so ``isProUnlocked()`` can query it
    /// directly instead of constructing a throwaway manager per call.
    private nonisolated static func scanCurrentEntitlements() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               StoreProduct(rawValue: transaction.productID) != nil {
                return true
            }
        }
        return false
    }

    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result,
               StoreProduct(rawValue: transaction.productID) != nil {
                state = .pro
                await transaction.finish()
            }
        }
    }
}

/// Errors surfaced by ``StoreManager.purchase(_:)`` and
/// ``StoreManager.restorePurchases()``.
enum StoreError: LocalizedError {
    case productNotFound
    case verificationFailed
    case userCancelled
    case pending
    case unknown

    var errorDescription: String? {
        switch self {
        case .productNotFound: return "商品未找到"
        case .verificationFailed: return "购买验证失败"
        case .userCancelled: return "已取消"
        case .pending: return "等待中"
        case .unknown: return "未知错误"
        }
    }

    /// Whether the error represents the user cancelling a StoreKit purchase
    /// sheet (`.userCancelled`). Paywall call sites use this to suppress the
    /// "已取消" error message.
    var isCancellation: Bool {
        if case .userCancelled = self { return true }
        return false
    }
}
