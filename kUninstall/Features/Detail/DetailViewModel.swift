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

    func restore(record: UninstallRecord) async {
        _ = await trashMover.restore(record: record)
        showUninstallToast = false
    }
}
