import Foundation

// MARK: - Product Identifiers

/// StoreKit product identifiers for the kFresh Pro unlock.
///
/// Raw values are the product IDs registered in App Store Connect and in
/// `Configuration.storekit` (StoreKit local testing).
enum StoreProduct: String, CaseIterable, Sendable {
    /// One-time (non-consumable) Pro unlock.
    case proUnlock = "app.kraftly.kfresh.pro"
}

// MARK: - Entitlement State

/// The entitlement state surfaced to the UI and to App Intents.
enum ProState: Equatable, Sendable {
    case free
    case pro
}

// MARK: - Test Override Key

/// UserDefaults key backing the Pro test override.
///
/// Shared by ``StoreManager`` (via `StoreManager.testOverrideKey`), the
/// `-kFreshTestPro` launch-argument parser in the app entry point, and the
/// Store/UI tests so the three can never drift apart.
let kFreshTestProOverrideKey = "kFresh.testProOverride"
