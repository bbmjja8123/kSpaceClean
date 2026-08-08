import StoreKit

@MainActor
public final class StoreManager: ObservableObject, StoreProtocol {
    @Published public var isSubscribed = false
    @Published public var isEligibleForTrial = true

    private let productID = "app.kraftly.sclean.subscription.yearly"

    public init() {}

    public func checkSubscription() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == productID && transaction.revocationDate == nil {
                    isSubscribed = true
                    return
                }
            }
        }
        isSubscribed = false
    }

    public func purchase() async {
        guard let product = try? await Product.products(for: [productID]).first else { return }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(.verified(let transaction)):
                await transaction.finish()
                isSubscribed = true
            default:
                break
            }
        } catch {
            print("Purchase failed: \(error)")
        }
    }

    public func restorePurchases() async {
        try? await AppStore.sync()
        await checkSubscription()
    }
}
