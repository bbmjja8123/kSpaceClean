import StoreKit

/// Single commerce surface for Klaris (P1 T7).
///
/// The retired model was a yearly subscription + 1 GB monthly free quota.
/// The current model is one non-consumable buyout: own
/// `app.kraftly.klaris.buyout` → every reclamation action unlocks
/// (`hasPurchased == true`); not owning it → the free tier, which keeps
/// scanning/attribution and refuses cleanups (R5).
@MainActor
public final class StoreManager: ObservableObject, StoreProtocol {
    @Published public var hasPurchased = false

    /// The single non-consumable product. Internal (not `private`) so tests
    /// can pin the identifier against the .storekit configuration.
    public static let productID = "app.kraftly.klaris.buyout"

    /// ProductIDs of the currently active (verified, non-revoked)
    /// entitlements. Injectable so tests can drive `checkSubscription()`
    /// without any StoreKit/network call.
    private let entitlements: @Sendable () async -> [String]

    /// Default reader: StoreKit's current entitlements, filtered to verified
    /// non-revoked transactions.
    private static func liveEntitlements() async -> [String] {
        var ids: [String] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.revocationDate == nil {
                ids.append(transaction.productID)
            }
        }
        return ids
    }

    public convenience init() {
        self.init(entitlements: StoreManager.liveEntitlements)
    }

    /// Test seam — internal so production callers keep the parameterless
    /// StoreKit-backed init.
    init(entitlements: @escaping @Sendable () async -> [String]) {
        self.entitlements = entitlements
    }

    /// Re-derive ownership from the active entitlements. Called once per
    /// launch (`AppGraph` wires it — fix r1: previously only purchase /
    /// restore / Settings re-derived it, so a purchased user who relaunched
    /// the app was refused and shown the paywall until they visited
    /// Settings). Also the restore path (`AppStore.sync()` refreshes
    /// `currentEntitlements`).
    public func checkSubscription() async {
        hasPurchased = await entitlements().contains(Self.productID)
    }

    public func purchase() async {
        guard let product = try? await Product.products(for: [Self.productID]).first else { return }
        do {
            let result = try await product.purchase()
            await handlePurchaseResult(result)
        } catch {
            Log.store.error("Purchase failed: \(error)")
        }
    }

    /// Non-consumable purchase-result handling. Internal so tests can drive
    /// the outcomes that must NOT grant ownership.
    func handlePurchaseResult(_ result: Product.PurchaseResult) async {
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                // Ownership check: the verified transaction must be for our
                // non-consumable and not revoked (e.g. refunded) before we
                // flip the gate.
                let owns = transaction.productID == Self.productID
                    && transaction.revocationDate == nil
                await transaction.finish()
                hasPurchased = owns
            case .unverified(_, let reason):
                Log.store.error("Purchase failed verification: \(String(describing: reason))")
            }
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    public func restorePurchases() async {
        try? await AppStore.sync()
        await checkSubscription()
    }
}
