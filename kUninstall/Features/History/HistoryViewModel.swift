import Foundation

@MainActor
class HistoryViewModel: ObservableObject {
    @Published var records: [UninstallRecord] = []
    @Published var isRestoring = false

    private let repo = UninstallHistoryRepository()

    func loadHistory() async {
        let all = await repo.fetchAll()
        await MainActor.run { self.records = all }
    }

    func restore(record: UninstallRecord) async {
        isRestoring = true
        let mover = TrashMover()
        _ = await mover.restore(record: record)
        await loadHistory()
        isRestoring = false
    }
}
