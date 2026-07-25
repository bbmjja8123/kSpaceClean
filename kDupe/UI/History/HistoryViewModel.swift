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
            records = try await repository.loadScanHistory(limit: 50)
        } catch {
            records = []
        }
    }

    func delete(_ record: ScanRecord) async {
        do {
            try await repository.deleteScan(id: record.id)
            records.removeAll { $0.id == record.id }
        } catch {
            // Handle error
        }
    }
}
