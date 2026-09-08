import Foundation
import StoreKit

/// Thin, `Sendable` boundary around StoreKit 2 so `StoreManager` can be unit
/// tested without spinning up a real StoreKit transaction. The default
/// production implementation wraps Apple's `Product` / `Transaction` APIs;
/// tests substitute an in-memory stub that returns canned values.
///
/// `Product` and `Transaction` are already `Sendable` in StoreKit 2, so the
/// only requirement for this protocol is that the methods themselves
/// participate in structured concurrency cleanly. `Sendable` conformance is
/// declared explicitly so types that hand the boundary to background tasks
/// (e.g. a transaction listener) can do so without `@unchecked`.
public protocol StoreKitClient: Sendable {
    /// Fetch StoreKit 2 `Product` metadata for the supplied identifiers.
    /// Wraps `Product.products(for:)` and may throw on network failure.
    func products(for ids: [String]) async throws -> [Product]

    /// Start a purchase for the given product. Mirrors `Product.purchase()`
    /// and propagates user-cancellation, pending, and verified/unverified
    /// results via the return value.
    func purchase(_ product: Product) async throws -> Product.PurchaseResult

    /// Iterate the user's currently entitled transactions. Wraps
    /// `Transaction.currentEntitlements`. The implementation must finish
    /// the sequence so callers can `for try await` over it.
    func currentEntitlements() async throws -> [Transaction]

    /// Ask StoreKit to sync the user's account. Mirrors `AppStore.sync()`.
    /// Used by the "Restore Purchases" affordance; throws on failure
    /// (including user-cancelled sign-in).
    func sync() async throws

    /// A long-lived stream of transaction updates pushed by StoreKit when
    /// a purchase completes, a renewal happens, or the App Store revokes
    /// an entitlement. Mirrors `Transaction.updates`. The implementation
    /// owns a detached `Task` that drains StoreKit's continuation.
    var updates: AsyncStream<Transaction> { get }
}

/// Production implementation of `StoreKitClient`. Forwards calls directly
/// to Apple's StoreKit 2 APIs and retains a detached task that drains
/// `Transaction.updates` for as long as the client is alive.
///
/// The stream is implemented with a manual continuation rather than a
/// re-publication of `Transaction.updates` so that the protocol can vend a
/// single `AsyncStream` to multiple consumers (each consumed via `for await`).
public final class LiveStoreKitClient: StoreKitClient, @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: AsyncStream<Transaction>.Continuation
    private var listenerTask: Task<Void, Never>?
    private let updatesStream: AsyncStream<Transaction>

    public init() {
        // Build the stream up-front and start the listener task in
        // `start()` so we can keep the protocol property `get`-only and
        // still drain StoreKit's `AsyncSequence` exactly once.
        var capturedContinuation: AsyncStream<Transaction>.Continuation!
        let stream = AsyncStream<Transaction>(bufferingPolicy: .bufferingNewest(64)) { continuation in
            capturedContinuation = continuation
        }
        self.updatesStream = stream
        self.continuation = capturedContinuation
        start()
    }

    deinit {
        continuation.finish()
        listenerTask?.cancel()
    }

    public func products(for ids: [String]) async throws -> [Product] {
        try await Product.products(for: ids)
    }

    public func purchase(_ product: Product) async throws -> Product.PurchaseResult {
        try await product.purchase()
    }

    public func currentEntitlements() async throws -> [Transaction] {
        var collected: [Transaction] = []
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                collected.append(transaction)
            case .unverified:
                continue
            }
        }
        return collected
    }

    public func sync() async throws {
        try await AppStore.sync()
    }

    public var updates: AsyncStream<Transaction> { updatesStream }

    /// Start the detached listener that drains `Transaction.updates` into
    /// the vended `AsyncStream`. Called automatically from `init`.
    private func start() {
        listenerTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { break }
                // `Transaction.updates` yields `VerificationResult<Transaction>`.
                // We only forward verified transactions; unverified payloads
                // are recorded by the manager through error plumbing.
                switch result {
                case .verified(let transaction):
                    self.yield(transaction)
                case .unverified:
                    continue
                }
            }
        }
    }

    private func yield(_ transaction: Transaction) {
        lock.lock()
        lock.unlock()
        continuation.yield(transaction)
    }
}

/// In-process stub used by tests. The stub never touches StoreKit and
/// returns canned responses wired up at construction time. Each call site
/// (purchase, entitlement refresh, restore) can be exercised independently
/// by assigning a new response before invoking the manager.
public final class StubStoreKitClient: StoreKitClient, @unchecked Sendable {
    /// Canned product list returned by `products(for:)`.
    public var productsResponse: [Product]

    /// When `true`, `products(for:)` throws `StoreKitError.networkError`
    /// instead of returning `productsResponse`. Exposed for tests that
    /// want to exercise the loadProducts error branch.
    public var _productsShouldThrow: Bool = false

    /// Canned purchase result returned by `purchase(_:)`. Updated between
    /// tests to simulate cancellation, success, and unverified outcomes.
    public var purchaseResult: Result<Product.PurchaseResult, Error>

    /// Canned entitlement list returned by `currentEntitlements()`.
    public var entitlements: [Transaction]

    /// When `true`, `currentEntitlements()` throws `StoreKitError.networkError`
    /// instead of returning `entitlements`. Exposed for tests that want
    /// to exercise the restore error branch.
    public var _entitlementsShouldThrow: Bool = false

    /// When `true`, `sync()` throws `StoreKitError.networkError` instead
    /// of returning. Exposed for tests that want to exercise the
    /// restore-error path independently of `currentEntitlements`.
    public var _syncShouldThrow: Bool = false

    /// Continuation backing the `updates` stream so tests can push
    /// simulated transaction updates at the manager.
    private let updatesStream: AsyncStream<Transaction>
    private let updatesContinuation: AsyncStream<Transaction>.Continuation

    public init(
        products: [Product] = [],
        purchaseResult: Result<Product.PurchaseResult, Error> = .success(.userCancelled),
        entitlements: [Transaction] = []
    ) {
        self.productsResponse = products
        self.purchaseResult = purchaseResult
        self.entitlements = entitlements

        // Note: the variables below are assigned through an immediately
        // invoked closure so we can capture the continuation before the
        // `AsyncStream` initializer returns.
        var capturedContinuation: AsyncStream<Transaction>.Continuation!
        let stream = AsyncStream<Transaction>(bufferingPolicy: .bufferingNewest(64)) { continuation in
            capturedContinuation = continuation
        }
        self.updatesStream = stream
        self.updatesContinuation = capturedContinuation
    }

    public func products(for ids: [String]) async throws -> [Product] {
        if _productsShouldThrow {
            throw StoreKitError.networkError(URLError(.notConnectedToInternet))
        }
        return productsResponse
    }

    public func purchase(_ product: Product) async throws -> Product.PurchaseResult {
        try purchaseResult.get()
    }

    public func currentEntitlements() async throws -> [Transaction] {
        if _entitlementsShouldThrow {
            throw StoreKitError.networkError(URLError(.notConnectedToInternet))
        }
        return entitlements
    }

    public func sync() async throws {
        if _syncShouldThrow {
            throw StoreKitError.networkError(URLError(.notConnectedToInternet))
        }
        // Test-only stub: return immediately.
    }

    public var updates: AsyncStream<Transaction> { updatesStream }

    /// Inject a simulated transaction update for tests.
    public func emit(_ transaction: Transaction) {
        updatesContinuation.yield(transaction)
    }

    /// Finish the `updates` stream for tests that want to assert teardown.
    public func finishUpdates() {
        updatesContinuation.finish()
    }
}

// MARK: - Test integration
//
// When a test needs a real StoreKit flow (e.g. integration with a verified
// `VerificationResult<Transaction>`), launch the suite under the
// `StoreKitTestConfiguration.storekit` test plan and use `SKTestSession`
// to purchase the configured product. `StubStoreKitClient` covers the
// cancellation / unverified / restore paths without requiring StoreKit.
