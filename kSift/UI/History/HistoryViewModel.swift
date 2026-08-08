import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var records: [ScanRecord] = []
    @Published var isLoading = false

    private let repository: DuplicateRepositoryProtocol

    init(repository: DuplicateRepositoryProtocol = DuplicateRepositoryCoreData()) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            records = try await repository.loadScanRecords()
        } catch {
            records = []
        }
    }

    func delete(_ record: ScanRecord) async {
        do {
            try await repository.deleteScanRecord(id: record.id)
            records.removeAll { $0.id == record.id }
        } catch {
            // Handle error
        }
    }
}
