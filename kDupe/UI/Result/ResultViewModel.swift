import SwiftUI
import Combine

@MainActor
final class ResultViewModel: ObservableObject {
    @Published var groups: [DuplicateGroup] = []
    @Published var selectedGroupIds: Set<UUID> = []
    @Published var activeCategory: DuplicateCategory?
    @Published var sortOrder: SortOrder = .sizeDesc
    @Published var isProcessing = false
    @Published var showCleanupConfirmation = false

    enum SortOrder: String, CaseIterable {
        case sizeDesc = "Size (High→Low)"
        case sizeAsc = "Size (Low→High)"
        case countDesc = "Count (High→Low)"
        case type = "Category"
    }

    var filteredGroups: [DuplicateGroup] {
        var result = groups
        if let cat = activeCategory {
            result = result.filter { $0.category == cat }
        }
        switch sortOrder {
        case .sizeDesc: result.sort { $0.totalSize > $1.totalSize }
        case .sizeAsc: result.sort { $0.totalSize < $1.totalSize }
        case .countDesc: result.sort { $0.files.count > $1.files.count }
        case .type: result.sort { $0.category.rawValue < $1.category.rawValue }
        }
        return result
    }

    var totalDuplicateSize: Int64 {
        groups.reduce(0) { $0 + $1.totalSize }
    }

    var totalGroupCount: Int { groups.count }

    func autoSelectGroups() {
        selectedGroupIds = Set(groups.map(\.id))
    }

    func clearSelection() {
        selectedGroupIds.removeAll()
    }

    func removeSelected(using manager: CleanupManager) async {
        isProcessing = true
        defer { isProcessing = false }
        let toRemove = groups.filter { selectedGroupIds.contains($0.id) }
        for group in toRemove {
            let toDelete = group.files.dropFirst().map { $0 }
            try? await manager.moveToTrash(Array(toDelete))
        }
        groups.removeAll { selectedGroupIds.contains($0.id) }
        selectedGroupIds.removeAll()
    }
}
