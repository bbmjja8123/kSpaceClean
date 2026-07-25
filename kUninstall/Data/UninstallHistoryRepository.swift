import Foundation

actor UninstallHistoryRepository {
    private var records: [UninstallRecord] = []

    func save(record: UninstallRecord) {
        records.append(record)
    }

    func fetchAll() -> [UninstallRecord] {
        records.sorted { $0.uninstalledAt > $1.uninstalledAt }
    }

    func fetch(id: UUID) -> UninstallRecord? {
        records.first { $0.id == id }
    }

    func markRestored(id: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        var record = records[idx]
        record.isRestored = true
        records[idx] = record
    }

    func deleteExpired(olderThan days: Int) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        records.removeAll { $0.uninstalledAt < cutoff }
    }
}
