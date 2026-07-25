import Foundation

public actor DuplicateRepositoryJSON: DuplicateRepositoryProtocol {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let storeURL: URL

    public init(storeURL: URL? = nil) {
        self.fileManager = .default
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        let baseURL = storeURL ?? fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: "group.app.kraftly.kdupe")!
        self.storeURL = baseURL.appendingPathComponent("kdupe_data.json")
    }

    public func saveScanRecord(_ record: ScanRecord) async throws {
        var records = try await loadAllRecords()
        records.insert(record, at: 0)
        let data = try encoder.encode(records)
        try data.write(to: storeURL, options: .atomic)
    }

    public func loadScanRecords() async throws -> [ScanRecord] {
        try await loadAllRecords()
    }

    public func loadScanRecord(id: UUID) async throws -> ScanRecord? {
        try await loadAllRecords().first { $0.id == id }
    }

    public func deleteScanRecord(id: UUID) async throws {
        var records = try await loadAllRecords()
        records.removeAll { $0.id == id }
        let data = try encoder.encode(records)
        try data.write(to: storeURL, options: .atomic)
    }

    public func saveCleanupAction(_ action: CleanupAction) async throws {
        // JSON repository does not persist individual actions
    }

    public func loadCleanupHistory() async throws -> [CleanupRecord] {
        []
    }

    private func loadAllRecords() async throws -> [ScanRecord] {
        guard fileManager.fileExists(atPath: storeURL.path) else { return [] }
        let data = try Data(contentsOf: storeURL)
        return try decoder.decode([ScanRecord].self, from: data)
    }
}
