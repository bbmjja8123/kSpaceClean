import Combine
import Foundation

/// Central registry of the app's long-lived services, injected into the view
/// hierarchy as an environment object so every screen shares one catalog, one
/// history store, one FDA probe, one ``StoreManager``, and — critically —
/// ONE ``TrashMover``.
///
/// The shared mover (C1) is built from the shared history repository so the
/// uninstall → history → restore loop never splits across two repositories:
/// a record saved by a `DetailViewModel`-driven uninstall is the exact same
/// record the History tab lists and the undo toast restores.
@MainActor
final class AppServices: ObservableObject {
    let catalog = AppCatalogService()
    let history = UninstallHistoryRepository()
    let fdaProbe = FDAPermissionProbe()
    let store = StoreManager()
    let mover: TrashMover

    init() {
        mover = TrashMover(historyRepo: history)
    }
}
