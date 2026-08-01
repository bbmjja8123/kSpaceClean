import Foundation
import SwiftUI

/// View-model for the Pro "深度清理" tab.
///
/// Drives ``DeepCleanView`` through a coarse-grained state machine
/// (`.idle` → `.scanning` → `.loaded` / `.failed`, plus a transient
/// `.cleaning` during a delete) and holds the user's current selection. The
/// engine is injected via ``DeepCleanEngining`` so tests can substitute an
/// in-memory stub.
///
/// The view-model is `@MainActor` so its `@Published` mutations are safe to
/// feed SwiftUI directly.
@MainActor
final class DeepCleanViewModel: ObservableObject {

    /// Coarse-grained state machine the view renders with a `switch`.
    /// `.loaded` carries the full item list (the view further groups by
    /// ``SystemCleanCategory`` via ``groupedItems``). `.failed` carries a
    /// localized message for the empty-state view to display.
    enum ViewState {
        case idle
        case scanning
        case loaded([SystemCleanItem])
        case cleaning
        case failed(String)
    }

    /// Visible state. `internal(set)` so the type stays `@MainActor`-pure
    /// for read access from the view; the view-model mutates it through
    /// `load()`, `toggle(_:)`, `clean()`.
    @Published internal(set) var state: ViewState = .idle

    /// IDs of the items the user has currently selected for cleaning.
    /// Populated by `load()` with every non-protected item (the Pro flow
    /// defaults to "safe everything") and mutated by `toggle(_:)`.
    @Published internal(set) var selectedIDs: Set<String> = []

    /// Number of items actually deleted by the most recent `clean()`.
    /// Lets the view surface partial-failure states ("已删除 X 项").
    @Published internal(set) var lastCleanCount: Int = 0

    private let engine: DeepCleanEngining

    /// Designated initializer. The engine is injected so the app coordinator
    /// can build a shared `DeepCleanEngine` and tests can substitute a stub.
    init(engine: DeepCleanEngining) {
        self.engine = engine
    }

    /// Loads items from the engine and transitions through
    /// `.scanning` → `.loaded` (or `.failed` on error). On success the
    /// selection is reset to every non-protected item — the Pro flow
    /// defaults to "safe everything", exactly like the risk-labeled
    /// checkboxes in the scan UI.
    func load() async {
        state = .scanning
        do {
            let items = try await engine.scan()
            state = .loaded(items)
            selectedIDs = Set(items.filter { !$0.isProtected }.map(\.id))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Toggles the supplied item in the selection. Protected items are
    /// always ignored, even if a future caller forwards one.
    func toggle(_ item: SystemCleanItem) {
        guard case .loaded = state, !item.isProtected else { return }
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    /// Returns whether the supplied item is currently selected. Used by the
    /// row's `Toggle` binding.
    func isSelected(_ item: SystemCleanItem) -> Bool {
        selectedIDs.contains(item.id)
    }

    /// Deletes the currently-selected items through the engine.
    ///
    /// Returns the number of items actually deleted (0 when the state is not
    /// `.loaded`, nothing is selected, or the engine throws). On success the
    /// list is reloaded so deleted rows disappear; on failure the state
    /// becomes `.failed` so the view can show the error.
    func clean() async -> Int {
        guard case .loaded(let items) = state else { return 0 }
        let selected = items.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return 0 }
        state = .cleaning
        do {
            let deleted = try await engine.clean(selected)
            lastCleanCount = deleted
            await load()
            return deleted
        } catch {
            state = .failed(error.localizedDescription)
            return 0
        }
    }

    /// Returns the loaded items bucketed by ``SystemCleanCategory``, sorted
    /// by the category's `rawValue` (alphabetical). Returns an empty array
    /// outside of `.loaded`.
    var groupedItems: [(SystemCleanCategory, [SystemCleanItem])] {
        guard case .loaded(let items) = state else { return [] }
        return Dictionary(grouping: items, by: \.category)
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { (category, items) in (category, items) }
    }

    /// The loaded items currently in the selection.
    var selectedItems: [SystemCleanItem] {
        guard case .loaded(let items) = state else { return [] }
        return items.filter { selectedIDs.contains($0.id) }
    }

    /// Aggregate size of the current selection, used by the bottom bar.
    var selectedSizeBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.sizeBytes }
    }
}
