import Foundation
import SwiftUI

/// View-model for the History tab. Loads the last 30 days of uninstall
/// records from `UninstallHistoryRepository` and drives the restore
/// flow against `TrashMover`.
///
/// Restoration is a non-throwing `Result`-returning call, so the
/// transition is modelled as an explicit `RestoreState` enum (rather
/// than throwing) and the row view reacts to whichever terminal
/// branch `.restored` / `.failed` lands on. Stays on `@MainActor` so
/// `@Published` mutations are always safe to drive SwiftUI directly.
@MainActor
final class HistoryViewModel: ObservableObject {

    /// Coarse-grained restore progress, observable per-row via
    /// `recordID` matching. `.restoring` → `.restored` | `.failed`.
    enum RestoreState: Equatable {
        case idle
        case restoring(recordID: UUID)
        case restored(recordID: UUID)
        case failed(recordID: UUID, message: String)
    }

    @Published internal(set) var records: [UninstallRecord] = []
    @Published internal(set) var restoreState: RestoreState = .idle

    private let historyRepo: UninstallHistoryRepository
    private let trashMover: TrashMover

    /// Designated initialiser. The repository and mover are injected
    /// so tests can share an in-memory store (see
    /// `TrashMover.init(auditLogger:historyRepo:)`).
    init(historyRepo: UninstallHistoryRepository, trashMover: TrashMover) {
        self.historyRepo = historyRepo
        self.trashMover = trashMover
    }

    /// Refreshes `records` from the repository, scoped to the last 30
    /// days and excluding records already marked restored (so the UI
    /// never offers to "restore" an app that's already back on disk).
    func loadHistory() async {
        let recent = await historyRepo.fetchAll(within: 30)
        records = recent.filter { !$0.isRestored }
    }

    /// Drives a single restore. Updates `restoreState` at each phase so
    /// the row view can show progress / success / error inline. On any
    /// terminal branch we re-run `loadHistory()` so the restored record
    /// disappears from the visible list.
    func restore(_ record: UninstallRecord) async {
        restoreState = .restoring(recordID: record.id)
        let result = await trashMover.restore(record: record)
        switch result {
        case .success:
            restoreState = .restored(recordID: record.id)
        case .failure(let error):
            restoreState = .failed(recordID: record.id, message: error.localizedDescription)
        }
        await loadHistory()
    }
}