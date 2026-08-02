import StoreKit
import Foundation

@MainActor
final class StoreManager: ObservableObject {
    /// The lifetime Pro SKU.
    nonisolated static let proProductID = ProductID.fullLicense.rawValue

    /// Free-tier cap before the user is nudged toward the paywall.
    /// Spec §1.4 locks this at 2 GB. `nonisolated` so unit tests can
    /// reference it from a non-MainActor test method.
    nonisolated static let freeCleanupQuotaBytes: Int64 = 2 * 1024 * 1024 * 1024

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPaidUser = false
    /// Lifetime total of bytes successfully moved to the Trash while the
    /// user was on the free tier. Persists across launches; reset only by
    /// purchasing Pro.
    @Published private(set) var freeTierBytesCleaned: Int64

    private static let freeBytesKey = "ksift.store.freeBytesCleaned"

    private var updatesTask: Task<Void, Never>?

    init() {
        self.freeTierBytesCleaned = UserDefaults.standard.object(forKey: Self.freeBytesKey) as? Int64 ?? 0
        // Observe transaction updates (renewals, refunds, Family Sharing)
        // for the lifetime of the app so Pro status flips without a
        // relaunch when, e.g., a Family Sharing invite is accepted.
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result,
                   transaction.productID == Self.proProductID {
                    await transaction.finish()
                    self.isPaidUser = true
                }
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: ProductID.allCases.map(\.rawValue))
        } catch {
            products = []
        }
        await refreshEntitlement()
    }

    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await transaction.finish()
                isPaidUser = true
                // Purchasing Pro resets the free-tier counter — the quota
                // is meaningless once the user has unlimited cleanup.
                setFreeBytesCleaned(0)
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

    /// Re-reads current entitlements. Used on launch and by "Restore
    /// Purchases" so a reinstall on a new Mac still flips to Pro.
    func refreshEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.proProductID {
                isPaidUser = true
                return
            }
        }
        isPaidUser = false
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    // MARK: - Free-tier quota

    /// Pure quota check (no StoreKit), kept static so it can be unit-tested
    /// without spinning up a paid/unpaid entitlement. `nonisolated` so
    /// callers from any actor (including non-MainActor tests) can use it.
    nonisolated static func canCleanup(
        cleanedSoFar: Int64,
        additionalBytes: Int64,
        isPaid: Bool
    ) -> Bool {
        isPaid || cleanedSoFar + additionalBytes <= freeCleanupQuotaBytes
    }

    /// Convenience for callers that already hold a StoreManager reference.
    func canCleanup(additionalBytes: Int64) -> Bool {
        Self.canCleanup(
            cleanedSoFar: freeTierBytesCleaned,
            additionalBytes: additionalBytes,
            isPaid: isPaidUser
        )
    }

    /// Call after a successful free-tier cleanup to roll the counter
    /// forward. No-op for Pro users (their counter stays at zero).
    func recordFreeTierCleanup(bytes: Int64) {
        guard !isPaidUser else { return }
        setFreeBytesCleaned(freeTierBytesCleaned + bytes)
    }

    private func setFreeBytesCleaned(_ value: Int64) {
        freeTierBytesCleaned = value
        UserDefaults.standard.set(value, forKey: Self.freeBytesKey)
    }
}