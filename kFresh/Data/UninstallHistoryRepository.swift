import Foundation

actor UninstallHistoryRepository {
    private var records: [UninstallRecord] = []

    func save(record: UninstallRecord) {
        records.append(record)
    }

    func fetchAll() -> [UninstallRecord] {
        records.sorted { $0.uninstalledAt > $1.uninstalledAt }
    }

    /// Returns uninstall records whose `uninstalledAt` falls within the given
    /// number of days, newest first. Non-throwing so the AppList scan can
    /// refresh the recent-uninstall section without error handling.
    func fetchAll(within days: Int) -> [UninstallRecord] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        return fetchAll().filter { $0.uninstalledAt >= cutoff }
    }

    /// Returns the uninstall record matching `id`, or `nil` if no record with
    /// that ID has been saved. Used by `TrashMover.historyRecord(id:)` and
    /// tests that need to assert post-conditions (e.g. `isRestored` flipped)
    /// without reaching into the private storage.
    func record(id: UUID) -> UninstallRecord? {
        records.first { $0.id == id }
    }

    func markRestored(id: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        var record = records[idx]
        record.isRestored = true
        records[idx] = record
    }

    /// Returns the most recent `limit` uninstall records (newest first) so
    /// callers (tests included) can inspect in-memory state without
    /// reaching into private storage.
    func recentRecords(limit: Int) -> [UninstallRecord] {
        Array(records.sorted { $0.uninstalledAt > $1.uninstalledAt }.prefix(limit))
    }

    func deleteExpired(olderThan days: Int) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        records.removeAll { $0.uninstalledAt < cutoff }
    }
}
