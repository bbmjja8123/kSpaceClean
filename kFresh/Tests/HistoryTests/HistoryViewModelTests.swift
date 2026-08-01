import XCTest
@testable import kFresh

@MainActor
final class HistoryViewModelTests: XCTestCase {

    // MARK: - Test fixtures

    /// Builds an in-memory repository + `TrashMover` pair that share the
    /// same backing store. The injected `init(auditLogger:historyRepo:)`
    /// constructor on `TrashMover` is the supported seam; the default
    /// production `init()` would create its own disk-backed repository
    /// which makes post-restore assertions vacuous (see I3b).
    private func makeRepoAndMover() -> (UninstallHistoryRepository, TrashMover) {
        let repo = UninstallHistoryRepository(inMemory: true)
        let mover = TrashMover(auditLogger: nil, historyRepo: repo)
        return (repo, mover)
    }

    /// Builds an `UninstallRecord` matching the real init signature at
    /// `kFresh/Core/Clean/TrashMover.swift:417`. The brief's signature
    /// was wrong in three ways: `actualTrashPath` is `String` (not
    /// `String?`), there is no `isFromDeepClean` field, and `residues:
    /// [ResidueFile]` is a required trailing positional argument.
    private func makeRecord(
        id: UUID = UUID(),
        appName: String = "Test",
        bundleID: String = "com.test",
        appPath: String = "/Applications/Test.app",
        appSize: Int64 = 1024,
        uninstalledAt: Date = Date(),
        isRestored: Bool = false
    ) -> UninstallRecord {
        UninstallRecord(
            id: id,
            appName: appName,
            bundleID: bundleID,
            appPath: appPath,
            actualTrashPath: "",
            appSize: appSize,
            totalResidueSize: 0,
            residueCount: Int32(0),
            uninstalledAt: uninstalledAt,
            isRestored: isRestored,
            backupPath: "",
            residues: []
        )
    }

    // MARK: - Tests

    func testLoadHistoryPopulatesRecords() async {
        let (repo, mover) = makeRepoAndMover()
        let record = makeRecord()
        await repo.save(record: record)

        let vm = HistoryViewModel(historyRepo: repo, trashMover: mover)
        await vm.loadHistory()

        XCTAssertEqual(vm.records.count, 1)
        XCTAssertEqual(vm.records.first?.appName, "Test")
    }

    func testRestoreStateTransitions() async {
        let (repo, mover) = makeRepoAndMover()
        let record = makeRecord()
        await repo.save(record: record)

        let vm = HistoryViewModel(historyRepo: repo, trashMover: mover)
        await vm.loadHistory()

        await vm.restore(record)

        // State should transition to .restored or .failed; never stuck on
        // .restoring — proves the do/catch in `restore(_:)` always reaches
        // the terminal branch.
        XCTAssertNotEqual(vm.restoreState, .restoring(recordID: record.id))
    }

    /// Defensive: when `markRestored(id:)` is invoked (via a successful
    /// `trashMover.restore` or via the repository directly), the next
    /// `loadHistory()` must exclude the restored record from the visible
    /// list so the UI never offers to "restore" an app that's already
    /// back on disk.
    func testLoadHistoryFiltersOutRestoredRecords() async {
        let (repo, mover) = makeRepoAndMover()
        let activeRecord = makeRecord(appName: "Active")
        let restorableRecord = makeRecord(appName: "Restorable")
        await repo.save(record: activeRecord)
        await repo.save(record: restorableRecord)

        // Simulate a previous successful restore by flipping the flag
        // directly on the backing repo. The HistoryViewModel's
        // `loadHistory()` must drop the flipped record from `records`.
        await repo.markRestored(id: activeRecord.id)

        let vm = HistoryViewModel(historyRepo: repo, trashMover: mover)
        await vm.loadHistory()

        XCTAssertEqual(vm.records.count, 1)
        XCTAssertEqual(vm.records.first?.appName, "Restorable")
    }
}