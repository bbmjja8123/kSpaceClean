import Foundation
import StoreKit
import Combine

/// Public, `@MainActor`-friendly surface for the StoreKit 2 paywall. The
/// protocol lets the rest of the app depend on a minimal interface while
/// tests substitute `StubStoreManager` without touching StoreKit.
///
/// Conformance is `Sendable`-bound so the view-model layer can pass the
/// manager across actor boundaries (e.g. into a background transaction
/// listener). `StoreManager` is annotated `@MainActor`, so this conformance
/// declaration is more about documentation than a compiler requirement.
public protocol StoreManagerProtocol: AnyObject, Sendable {
    /// The App Store Connect product identifier, e.g. `app.kraftly.kwatch.pro`.
    var productID: String { get }

    /// Products currently loaded from the App Store. Empty until the
    /// manager has finished loading.
    var products: [Product] { get }

    /// Local mirror of `PurchaseState.isPro`. The manager keeps it in sync
    /// by observing `PurchaseState.$isPro` so SwiftUI views do not have to
    /// combine two `@Published` sources.
    var isPro: Bool { get }

    /// The currently published product, or `nil` while products are loading
    /// or when no configuration is available.
    var primaryProduct: Product? { get }

    /// Kick off the initial product fetch and start listening to
    /// `Transaction.updates`. Safe to call multiple times.
    func refreshEntitlements() async

    /// Refresh the product metadata. Used by the paywall and pull-to-refresh.
    func loadProducts() async

    /// Start a StoreKit 2 purchase for the primary product. The manager
    /// blocks until the system surface dismisses, then surfaces verified
    /// transactions through `PurchaseState` and errors through
    /// `PurchaseState.recordError`.
    func purchase() async

    /// Re-check `Transaction.currentEntitlements` and trigger an
    /// `AppStore.sync()` so the user can recover a Pro entitlement on a
    /// new device. Updates `PurchaseState.isPro` accordingly.
    func restore() async

    /// Wrap up a verified transaction so StoreKit marks it as finished and
    /// stops redelivering it through `Transaction.updates`.
    func finish(_ transaction: Transaction) async
}

/// `@MainActor`-isolated StoreKit 2 manager. Mirrors `PurchaseState.isPro`
/// into a local `@Published` property so SwiftUI views can simply observe
/// `storeManager` without importing `PurchaseState`.
///
/// `@unchecked Sendable` matches the surrounding `@MainActor` factories
/// (e.g. `LiveAppContainer`, `TestAppContainer`) and lets the protocol
/// declare `Sendable` conformance for cross-actor hand-off (notably
/// the long-lived `Transaction.updates` listener task).
@MainActor
public final class StoreManager: StoreManagerProtocol, ObservableObject, @unchecked Sendable {
    // MARK: - Public state

    public let productID: String

    @Published public private(set) var products: [Product] = []

    @Published public private(set) var isPro: Bool

    public var primaryProduct: Product? { products.first }

    // MARK: - Dependencies

    private let client: any StoreKitClient
    private let purchaseState: PurchaseState
    private var purchaseCancellable: AnyCancellable?
    private var updatesListenerTask: Task<Void, Never>?

    // MARK: - Init

    /// Create a manager bound to the given `PurchaseState`. The default
    /// `client` talks to Apple's StoreKit 2 APIs; tests substitute
    /// `StubStoreKitClient` via the second parameter.
    public init(
        productID: String = "app.kraftly.kwatch.pro",
        purchaseState: PurchaseState,
        client: any StoreKitClient = LiveStoreKitClient()
    ) {
        self.productID = productID
        self.purchaseState = purchaseState
        self.client = client
        self.isPro = purchaseState.isPro
        observePurchaseState()
    }

    // MARK: - Lifecycle

    /// Fetch products, drain `currentEntitlements`, and spin up the
    /// long-lived `Transaction.updates` listener. Idempotent.
    public func refreshEntitlements() async {
        await loadProducts()
        await reconcileEntitlements()
        startUpdatesListener()
    }

    /// Refresh `products` from StoreKit. Errors surface through
    /// `PurchaseState.recordError` so the paywall can show them inline.
    public func loadProducts() async {
        do {
            let fetched = try await client.products(for: [productID])
            products = fetched
            purchaseState.clearError()
        } catch {
            purchaseState.recordError(
                Self.localizedMessage(for: error)
            )
        }
    }

    /// Start the listener that forwards `Transaction.updates` from the
    /// StoreKit client into `reconcileEntitlements`. The task is retained
    /// for the lifetime of the manager.
    private func startUpdatesListener() {
        guard updatesListenerTask == nil else { return }
        let client = self.client
        let productID = self.productID
        updatesListenerTask = Task { @MainActor [weak self] in
            for await transaction in client.updates {
                guard transaction.productID == productID else { continue }
                await self?.handle(transaction: transaction)
            }
        }
    }

    // MARK: - Purchase

    /// Buy the primary product. Verified transactions mark the user as Pro
    /// and get finished so StoreKit stops re-delivering them.
    public func purchase() async {
        guard let product = primaryProduct else {
            await loadProducts()
            guard let product = primaryProduct else {
                purchaseState.recordError(
                    "Pro is temporarily unavailable. Try again later."
                )
                return
            }
            await runPurchase(for: product)
            return
        }
        await runPurchase(for: product)
    }

    private func runPurchase(for product: Product) async {
        do {
            let result = try await client.purchase(product)
            switch result {
            case .success(let verification):
                await handle(verification: verification)
            case .userCancelled:
                // Cancellation is not an error — leave the user where they
                // were and clear any lingering message.
                purchaseState.clearError()
            case .pending:
                purchaseState.recordError(
                    "Your purchase is pending approval. We'll unlock Pro once it completes."
                )
            @unknown default:
                purchaseState.recordError(
                    "An unexpected purchase state occurred. Please try again."
                )
            }
        } catch {
            purchaseState.recordError(Self.localizedMessage(for: error))
        }
    }

    /// Handle a verified purchase. Finishes the transaction so StoreKit
    /// does not redeliver it via `Transaction.updates` on next launch.
    private func handle(verification: VerificationResult<Transaction>) async {
        switch verification {
        case .verified(let transaction):
            await handle(transaction: transaction)
        case .unverified(let transaction, let error):
            // Server returned a transaction we cannot cryptographically
            // verify — surface the underlying failure but do not grant Pro.
            purchaseState.recordError(
                "Purchase could not be verified: \(error.localizedDescription)"
            )
            await finish(transaction)
        }
    }

    private func handle(transaction: Transaction) async {
        guard transaction.productID == productID else { return }
        guard transaction.revocationDate == nil else {
            // The App Store revoked the entitlement; revert immediately.
            purchaseState.update(isPro: false)
            await finish(transaction)
            return
        }
        purchaseState.update(isPro: true)
        purchaseState.clearError()
        await finish(transaction)
    }

    /// Tell StoreKit the transaction can be considered finished.
    public func finish(_ transaction: Transaction) async {
        await transaction.finish()
    }

    // MARK: - Restore

    /// Re-check the user's existing entitlements and set Pro if any verified
    /// transaction matches the configured product. Triggers
    /// `AppStore.sync()` first so devices that just got a new App Store
    /// account sign-in pick up the latest transactions, then re-reads
    /// `currentEntitlements` and reconciles the Pro flag accordingly.
    public func restore() async {
        do {
            // Ask the client to sync with the user's account. The default
            // `LiveStoreKitClient` forwards to `AppStore.sync()`; tests
            // substitute a stub that returns immediately.
            try await client.sync()
            await reconcileEntitlements()
            purchaseState.clearError()
        } catch {
            purchaseState.recordError(Self.localizedMessage(for: error))
        }
    }

    private func reconcileEntitlements() async {
        do {
            let entitlements = try await client.currentEntitlements()
            let ownsProduct = entitlements.contains { transaction in
                transaction.productID == productID && transaction.revocationDate == nil
            }
            purchaseState.update(isPro: ownsProduct)
        } catch {
            // Fail open: if StoreKit is unreachable, leave the existing
            // value alone rather than locking the user out.
        }
    }

    // MARK: - PurchaseState observation

    private func observePurchaseState() {
        // Mirror the latest Pro flag so SwiftUI views reading `isPro` from
        // the manager immediately reflect outside mutations (e.g. a future
        // Family Sharing path).
        purchaseCancellable = purchaseState.$isPro
            .receive(on: RunLoop.main)
            .sink { [weak self] newValue in
                self?.isPro = newValue
            }
    }

    // MARK: - Error formatting

    /// Translate StoreKit errors to user-facing copy. Centralised so
    /// callers do not have to know the exact StoreKit error codes.
    private static func localizedMessage(for error: Error) -> String {
        if let storeError = error as? StoreKitError {
            switch storeError {
            case .networkError:
                return "Network unavailable. Check your connection and try again."
            case .userCancelled:
                return ""
            case .notAvailableInStorefront:
                return "Pro is not available in your storefront yet."
            case .notEntitled:
                return "Your previous purchase could not be restored."
            case .systemError:
                return "The App Store is currently unavailable. Try again later."
            @unknown default:
                return "We couldn't complete your purchase. Try again later."
            }
        }
        return error.localizedDescription
    }
}

/// Test-only stub for `StoreManagerProtocol`. Lets `TestAppContainer`
/// construct an `AppContainerProtocol` without instantiating
/// `StoreManager` (which would otherwise build a `LiveStoreKitClient`).
public final class StubStoreManager: StoreManagerProtocol, ObservableObject, @unchecked Sendable {
    public let productID: String
    @Published public var products: [Product]
    @Published public var isPro: Bool

    /// Canned results consumed by `purchase()` and `restore()`. Tests
    /// set these before invoking the manager to drive specific outcomes.
    public var purchaseBehavior: () async -> Void = {}
    public var restoreBehavior: () async -> Void = {}

    /// Mirrors the live `PurchaseState` so the stub reacts to outside
    /// mutations the same way a real manager would. Existing tests that
    /// construct a stub without a state can still drive the flag
    /// directly.
    private let purchaseState: PurchaseState?

    public init(
        productID: String = "app.kraftly.kwatch.pro",
        products: [Product] = [],
        isPro: Bool = false,
        purchaseState: PurchaseState? = nil
    ) {
        self.productID = productID
        self.products = products
        self.isPro = isPro
        self.purchaseState = purchaseState
    }

    public var primaryProduct: Product? { products.first }

    public func refreshEntitlements() async {
        // No-op for tests.
    }

    public func loadProducts() async {}

    public func purchase() async {
        await purchaseBehavior()
    }

    public func restore() async {
        await restoreBehavior()
    }

    public func finish(_ transaction: Transaction) async {
        _ = transaction
    }
}
