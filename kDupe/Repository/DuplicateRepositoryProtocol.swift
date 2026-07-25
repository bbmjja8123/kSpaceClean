import Foundation

public protocol DuplicateRepositoryProtocol: Sendable {
    func saveScanRecord(_ record: ScanRecord) async throws
    func loadScanRecords() async throws -> [ScanRecord]
    func loadScanRecord(id: UUID) async throws -> ScanRecord?
    func deleteScanRecord(id: UUID) async throws
    func saveCleanupAction(_ action: CleanupAction) async throws
    func loadCleanupHistory() async throws -> [CleanupRecord]
}

public struct ScanRecord: Sendable, Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let profileType: ProfileType
    public let totalFilesScanned: Int
    public let totalDuplicatesFound: Int
    public let totalWasteSize: Int64
    public let duration: TimeInterval
    public let groups: [DuplicateGroup]

    public init(id: UUID, timestamp: Date, profileType: ProfileType, totalFilesScanned: Int,
                totalDuplicatesFound: Int, totalWasteSize: Int64, duration: TimeInterval, groups: [DuplicateGroup]) {
        self.id = id
        self.timestamp = timestamp
        self.profileType = profileType
        self.totalFilesScanned = totalFilesScanned
        self.totalDuplicatesFound = totalDuplicatesFound
        self.totalWasteSize = totalWasteSize
        self.duration = duration
        self.groups = groups
    }
}
