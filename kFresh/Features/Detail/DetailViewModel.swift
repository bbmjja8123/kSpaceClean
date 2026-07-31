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
            for i in stride(from: 10, through: 0, by: -1) {
                undoRemainingSeconds = i
                try? await Task.sleep(nanoseconds: 1_000_000_000)
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
        _ = await trashMover.restore(record: record)
        showUninstallToast = false
        lastUninstallRecord = nil
    }
}
