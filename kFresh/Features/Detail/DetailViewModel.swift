import SwiftUI

@MainActor
class DetailViewModel: ObservableObject {
    @Published var app: InstalledApp
    @Published var showConfirmSheet = false
    @Published var selectedResidues: Set<String> = []
    @Published var isUninstalling = false
    @Published var showUninstallToast = false
    @Published var undoRemainingSeconds = 10
    @Published var analysis: AppAnalysis?
    /// The persisted uninstall record returned by `TrashMover.moveToTrash`.
    /// The undo button MUST pass this exact record to `TrashMover.restore`
    /// so that `actualTrashPath` (the Finder-de-duplicated `~/.Trash/...`
    /// path captured at uninstall time) is available — restoring without
    /// it forces the mover to guess the path, which breaks on Finder
    /// rename collisions like `Foo.app` → `Foo 2.app`.
    @Published var lastUninstallRecord: UninstallRecord?

    /// The most recent `TrashMover.restore` failure, or `nil` if the last
    /// restore attempt succeeded (or none has run yet).
    ///
    /// I3a: surfaced by `restore()` to drive a retry affordance. When
    /// `.restoreResidueFailed` (or any other failure) fires, the backup
    /// directory is intentionally preserved so the user can retry — but
    /// only if `lastUninstallRecord` is still available. The UI should
    /// observe this property and replace the undo countdown toast with a
    /// persistent "Restore partially failed — backup preserved, tap to
    /// retry" banner. Cleared on a subsequent successful restore.
    @Published var lastRestoreError: TrashError?

    private let trashMover = TrashMover()
    private let coordinator: AppCoordinator
    private let analysisRepo = AppAnalysisRepository()

    init(app: InstalledApp, coordinator: AppCoordinator) {
        self.app = app
        self.coordinator = coordinator
        self.selectedResidues = Set(app.residues.filter { $0.confidence >= 0.8 }.map { $0.id })
        Task { await loadAnalysis() }
    }

    private func loadAnalysis() async {
        let fetched = await analysisRepo.fetchAnalysis(bundleID: app.bundleID)
        await MainActor.run { self.analysis = fetched }
    }

    var totalFreedBytes: Int64 {
        app.sizeBytes + app.residues.filter { selectedResidues.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
    }

    func uninstall() async {
        isUninstalling = true
        let selected = app.residues.filter { selectedResidues.contains($0.id) }
        let result = await trashMover.moveToTrash(app: app, residues: selected)
        isUninstalling = false

        switch result {
        case .success(let record):
            // Persist the record returned by moveToTrash so the undo
            // button can restore from the EXACT trash path Finder
            // produced (including `Foo 2.app` style dedup). A
            // reconstructed record would have an empty
            // `actualTrashPath`, forcing `restore` to guess and break
            // on rename collisions.
            lastUninstallRecord = record
            showConfirmSheet = false
            showUninstallToast = true
            startUndoCountdown(with: record)
        case .failure(let error):
            break
        }
    }

    private func startUndoCountdown(with record: UninstallRecord) {
        undoRemainingSeconds = 10
        Task {
            // m7: `do`/`catch` instead of `try?` so cancellation (which
            // throws `CancellationError` inside `Task.sleep`) exits the
            // countdown cleanly. The previous `try? await Task.sleep(...)`
            // silently turned cancellation into a no-op, so a SwiftUI view
            // that destroyed `DetailViewModel` mid-countdown would still
            // observe the next tick.
            for i in stride(from: 10, through: 0, by: -1) {
                undoRemainingSeconds = i
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                if i == 0 {
                    showUninstallToast = false
                }
            }
        }
    }

    func restore() async {
        // Restore uses the persisted record from moveToTrash, which
        // carries `actualTrashPath`. If uninstall never ran (or
        // failed), `lastUninstallRecord` is nil — bail silently rather
        // than constructing a broken record with an empty trash path.
        guard let record = lastUninstallRecord else { return }
        let result = await trashMover.restore(record: record)
        // I3a: switch on the result so each failure mode drives a distinct
        // UI outcome instead of always clearing the undo affordance.
        // `.restoreResidueFailed` (and any other failure) means the app
        // bundle is already back at its original path BUT the residue
        // restore partially failed — the backup is intentionally preserved
        // for retry. Clearing `lastUninstallRecord` here would destroy the
        // user's only retry affordance.
        switch result {
        case .success:
            lastRestoreError = nil
            showUninstallToast = false
            lastUninstallRecord = nil
        case .failure(let error):
            // Keep `lastUninstallRecord` so the undo button can retry.
            // Surface the failure via `lastRestoreError` so the UI can
            // show "Restore partially failed — backup preserved, tap to
            // retry" (e.g. a persistent error banner replacing the
            // countdown toast).
            lastRestoreError = error
        }
    }
}
