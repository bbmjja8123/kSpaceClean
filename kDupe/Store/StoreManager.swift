import StoreKit
import Foundation

@MainActor
final class StoreManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isPaidUser = false

    func loadProducts() async {
        do {
            products = try await Product.products(for: ProductID.allCases.map(\.rawValue))
        } catch {
            products = []
        }
    }

    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await transaction.finish()
                isPaidUser = true
                return true
            }
            return false
        case .pending:
            return false
        case .userCancelled:
            return false
        @unknown default:
            return false
        }
    }

    func checkEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID.contains("app.kraftly.kdupe") {
                    isPaidUser = true
                    return
                }
            }
        }
        isPaidUser = false
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await checkEntitlement()
    }
}
