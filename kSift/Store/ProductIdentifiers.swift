import Foundation

/// The single Pro SKU. The spec locks this as a one-time $9.99 buyout
/// (Non-Consumable) — subscriptions were explicitly rejected as a poor
/// fit for a low-frequency utility.
enum ProductID: String, CaseIterable {
    case fullLicense = "app.kraftly.ksift.full_license"
}