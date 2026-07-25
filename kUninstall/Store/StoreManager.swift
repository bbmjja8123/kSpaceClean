import Foundation
import StoreKit

// MARK: - Store Manager

actor StoreManager {
    static let shared = StoreManager()

    private var isPurchased = false
    private var cachedProducts: [Product] = []

    // MARK: - Queries

    var isPro: Bool { isPurchased }

    func loadProducts() async -> [Product] {
        if !cachedProducts.isEmpty {
            return cachedProducts
        }
        let products = (try? await Product.products(for: [StoreProduct.proUnlock.rawValue])) ?? []
        cachedProducts = products
        return products
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async -> Bool {
        guard let result = try? await product.purchase() else { return false }
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                isPurchased = true
                await transaction.finish()
                return true
            }
            return false
        case .userCancelled:
            return false
        default:
            return false
        }
    }

    // MARK: - Restore

    func restorePurchases() async -> Bool {
        try? await AppStore.sync()
        isPurchased = await verifyReceipt()
        return isPurchased
    }

    // MARK: - Receipt Verification

    private func verifyReceipt() async -> Bool {
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              FileManager.default.fileExists(atPath: receiptURL.path) else {
            return false
        }
        // v1: receipt existence check is sufficient for sandbox testing.
        // Production should use local receipt validation or server-side verification.
        return true
    }
}
