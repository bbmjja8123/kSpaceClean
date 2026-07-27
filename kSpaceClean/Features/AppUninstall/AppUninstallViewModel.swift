import Foundation
import Combine

// MARK: - ViewModel

@MainActor
public final class AppUninstallViewModel: ObservableObject {
    @Published public var entries: [UninstallAppEntry] = []
    @Published public var isScanning = false
    @Published public var sortBy: SortField = .name
    @Published public var sortAscending = true

    public enum SortField: String, CaseIterable, Sendable {
        case name
        case size
        case leftoverSize

        public var displayName: String {
            switch self {
            case .name: return "名称"
            case .size: return "总大小"
            case .leftoverSize: return "残留大小"
            }
        }
    }

    private let scanner = AppUninstallScanner()

    // MARK: - Scanning

    public func startScan() {
        guard !isScanning else { return }
        isScanning = true
        entries = []

        Task {
            let result = await Task.detached {
                self.scanner.scan()
            }.value

            self.entries = self.sorted(result)
            self.isScanning = false
        }
    }

    // MARK: - Selection

    public func toggleSelection(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isSelected.toggle()
    }

    public func selectAll() {
        for index in entries.indices {
            entries[index].isSelected = true
        }
    }

    public func deselectAll() {
        for index in entries.indices {
            entries[index].isSelected = false
        }
    }

    /// Entries currently marked for uninstall, sorted by total size descending.
    public var selectedEntries: [UninstallAppEntry] {
        entries.filter(\.isSelected).sorted { $0.totalSize > $1.totalSize }
    }

    /// Total reclaimable space from all selected entries.
    public var selectedSize: Int64 {
        selectedEntries.reduce(0) { $0 + $1.totalSize }
    }

    /// Number of entries that have at least one leftover file.
    public var appsWithLeftovers: Int {
        entries.filter { $0.leftoverSize > 0 }.count
    }

    // MARK: - Sorting

    public func toggleSort(_ field: SortField) {
        if sortBy == field {
            sortAscending.toggle()
        } else {
            sortBy = field
            sortAscending = field == .name // default ascending for name, descending for sizes
        }
        entries = sorted(entries)
    }

    private func sorted(_ items: [UninstallAppEntry]) -> [UninstallAppEntry] {
        switch sortBy {
        case .name:
            return sortAscending
                ? items.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
                : items.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedDescending }
        case .size:
            return sortAscending
                ? items.sorted { $0.totalSize < $1.totalSize }
                : items.sorted { $0.totalSize > $1.totalSize }
        case .leftoverSize:
            return sortAscending
                ? items.sorted { $0.leftoverSize < $1.leftoverSize }
                : items.sorted { $0.leftoverSize > $1.leftoverSize }
        }
    }

    // MARK: - Uninstall

    /// Uninstalls all currently selected entries.
    /// - Returns: A tuple of succeeded app names and failed app names.
    public func uninstallSelected() async -> (succeeded: [String], failed: [String]) {
        let targets = selectedEntries
        guard !targets.isEmpty else { return ([], []) }

        var succeeded: [String] = []
        var failed: [String] = []

        for entry in targets {
            do {
                try await scanner.uninstall(entry: entry)
                succeeded.append(entry.appName)
            } catch {
                failed.append(entry.appName)
            }
        }

        // Remove successfully uninstalled entries from the list.
        entries.removeAll { entry in
            succeeded.contains(entry.appName)
        }

        return (succeeded, failed)
    }
}
