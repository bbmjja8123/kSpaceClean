import Combine
import Foundation

/// Central registry of the app's long-lived services, injected into the view
/// hierarchy as an environment object so every screen shares one catalog, one
/// history store, and one FDA probe.
@MainActor
final class AppServices: ObservableObject {
    let catalog = AppCatalogService()
    let history = UninstallHistoryRepository()
    let fdaProbe = FDAPermissionProbe()
}
