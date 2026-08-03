import SwiftUI
import Combine

@MainActor
final class ResultViewModel: ObservableObject {
    @Published var groups: [DuplicateGroup] = []
    @Published var selectedGroupIds: Set<UUID> = []
    @Published var activeCategory: DuplicateCategory?
    @Published var sortOrder: SortOrder = .sizeDesc
    @Published var searchText: String = ""
    @Published var isProcessing = false
    @Published var showCleanupConfirmation = false

    enum SortOrder: String, CaseIterable {
        case sizeDesc = "Size (High→Low)"
        case sizeAsc = "Size (Low→High)"
        case countDesc = "Count (High→Low)"
        case wasteDesc = "Reclaimable (High→Low)"
        case type = "Category"
    }

    var filteredGroups: [DuplicateGroup] {
        var result = groups
        if let cat = activeCategory {
            result = result.filter { $0.category == cat }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { group in
                group.files.contains { $0.url.lastPathComponent.localizedCaseInsensitiveContains(query) }
            }
        }
        switch sortOrder {
        case .sizeDesc: result.sort { $0.totalSize > $1.totalSize }
        case .sizeAsc: result.sort { $0.totalSize < $1.totalSize }
        case .countDesc: result.sort { $0.files.count > $1.files.count }
        case .wasteDesc: result.sort { ($0.totalSize - ($0.files.map(\.size).max() ?? 0)) > ($1.totalSize - ($1.files.map(\.size).max() ?? 0)) }
        case .type: result.sort { $0.category.rawValue < $1.category.rawValue }
        }
        return result
    }

    var totalDuplicateSize: Int64 {
        groups.reduce(0) { $0 + $1.totalSize }
    }

    var totalGroupCount: Int { groups.count }

    /// Replaces the displayed groups (from a scan hand-off or a history record).
    /// Resets selection and category filter so stale state cannot leak between loads.
    func loadGroups(_ newGroups: [DuplicateGroup]) {
        groups = newGroups
        selectedGroupIds.removeAll()
        activeCategory = nil
    }

    func autoSelectGroups() {
        selectedGroupIds = Set(groups.map(\.id))
    }

    func clearSelection() {
        selectedGroupIds.removeAll()
    }

    /// Trashes all-but-the-newest copy of every selected group (same semantics as
    /// GroupDetailView's "Auto Keep Newest"), returning the per-file failures the
    /// vault reported. Groups with any failure stay in the list for retry.
    @discardableResult
    func removeSelected(using manager: CleanupManager) async -> [VaultMoveFailure] {
        isProcessing = true
        defer { isProcessing = false }
        var failures: [VaultMoveFailure] = []
        var keepGroupIds: Set<UUID> = []
        let toRemove = groups.filter { selectedGroupIds.contains($0.id) }

        for group in toRemove {
            let newestFirst = group.files.sorted { $0.modificationDate > $1.modificationDate }
            let toDelete = newestFirst.dropFirst() // keep the newest copy
            guard !toDelete.isEmpty else { continue }
            do {
                let result = try await manager.moveToTrash(Array(toDelete))
                failures.append(contentsOf: result.failures)
                if !result.failures.isEmpty { keepGroupIds.insert(group.id) }
            } catch {
                failures.append(VaultMoveFailure(
                    url: group.files.first?.url ?? URL(fileURLWithPath: "/"),
                    reason: error.localizedDescription
                ))
                keepGroupIds.insert(group.id)
            }
        }

        groups.removeAll { selectedGroupIds.contains($0.id) && !keepGroupIds.contains($0.id) }
        selectedGroupIds.removeAll()
        return failures
    }
}
