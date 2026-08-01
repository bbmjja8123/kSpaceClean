import Foundation
import SwiftUI

/// View-model for the "启动项" tab. Drives the master list of
/// ``StartupItem`` rows grouped by ``StartupItemType``, plus the toggle /
/// remove actions forwarded to ``StartupItemManager``.
///
/// The view-model is `@MainActor` so its `@Published` mutations are
/// safe to feed SwiftUI directly. The manager is injected via the
/// ``StartupItemManaging`` protocol so tests can use an in-memory stub
/// (see ``StartupItemsViewModelTests/StubManager``).
@MainActor
final class StartupItemsViewModel: ObservableObject {

    /// Coarse-grained state machine the view renders with a `switch`.
    /// `.loaded` carries the full items list (the view further groups by
    /// `type` via ``groupedByType``). `.failed` carries a localized
    /// message for the empty-state view to display.
    ///
    /// `Equatable` is intentionally not declared because `StartupItem`
    /// has no `Equatable` conformance — we only pattern-match in the
    /// view, never compare states directly.
    enum ViewState {
        case idle
        case loading
        case loaded([StartupItem])
        case failed(String)
    }

    /// Visible state. `internal(set)` so the type stays `@MainActor`-pure
    /// for read access from the view; the view-model mutates it through
    /// `load()`, `toggle(_:)`, `remove(_:)`.
    @Published internal(set) var state: ViewState = .idle

    private let manager: StartupItemManaging

    /// Designated initializer. The manager is injected so the app
    /// coordinator can share a single `StartupItemManager` instance
    /// across tabs and tests can substitute a stub.
    init(manager: StartupItemManaging) {
        self.manager = manager
    }

    /// Loads items from the manager and transitions through
    /// `.loading` → `.loaded` (or `.failed` on error). Idempotent —
    /// calling `load()` while already `.loaded` re-fetches from the
    /// manager.
    func load() async {
        state = .loading
        do {
            let items = try await manager.listItems()
            state = .loaded(items)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Toggles the supplied item's enabled state via the manager, then
    /// re-runs `load()` so the visible list reflects the new value.
    /// Failures are silently absorbed here for v1; a future iteration
    /// surfaces them through a separate `@Published var lastError: String?`.
    func toggle(_ item: StartupItem) async {
        do {
            try await manager.setEnabled(!item.enabled, for: item)
            await load()
        } catch {
            // v1: swallow — row stays in place until the user reloads.
        }
    }

    /// Moves the supplied item out of `launchd` via the manager, then
    /// re-runs `load()` so the row disappears from the list.
    /// Failures are silently absorbed (see `toggle(_:)` for context).
    func remove(_ item: StartupItem) async {
        do {
            try await manager.remove(item)
            await load()
        } catch {
            // v1: swallow.
        }
    }

    /// Returns the loaded items bucketed by ``StartupItemType``, sorted
    /// by the type's `rawValue`. Returns an empty array outside of
    /// `.loaded`.
    var groupedByType: [(StartupItemType, [StartupItem])] {
        guard case .loaded(let items) = state else { return [] }
        return Dictionary(grouping: items, by: \.type)
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { (type, items) in (type, items) }
    }
}
