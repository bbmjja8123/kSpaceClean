import Foundation
import DetectionCore

actor MockDuplicateRepository: DuplicateRepositoryProtocol {
    private var _savedRecords: [ScanRecord] = []
    private var _deletedRecordIDs: [UUID] = []
    private var _loadedRecordID: UUID?
    private var _recordsToReturn: [ScanRecord] = []

    init(records: [ScanRecord] = []) {
        _recordsToReturn = records
    }

    func saveScanRecord(_ record: ScanRecord) async throws {
        _savedRecords.append(record)
    }

    func loadScanRecords() async throws -> [ScanRecord] {
        _recordsToReturn
    }

    func loadScanRecord(id: UUID) async throws -> ScanRecord? {
        _loadedRecordID = id
        return _recordsToReturn.first { $0.id == id }
    }

    func deleteScanRecord(id: UUID) async throws {
        _deletedRecordIDs.append(id)
    }

    func saveCleanupAction(_ action: CleanupAction) async throws {
        // no-op for scan orchestrator tests
    }

    func loadCleanupHistory() async throws -> [CleanupRecord] {
        []
    }

    // MARK: Test accessors (called from outside the actor)

    func savedRecords() async -> [ScanRecord] { _savedRecords }
    func deletedRecordIDs() async -> [UUID] { _deletedRecordIDs }
    func loadedRecordID() async -> UUID? { _loadedRecordID }
}
