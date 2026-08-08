import Foundation
import SwiftUI

/// Sort field options exposed in the LargeOldView.
public enum LargeOldSortField: String, CaseIterable, Identifiable, Sendable {
    case size = "Size"
    case date = "Date"
    case name = "Name"
    case path = "Path"

    public var id: String { rawValue }
}

/// Main-actor view model that drives ``LargeOldView``.
@MainActor
public final class LargeOldViewModel: ObservableObject {
    // MARK: Published

    @Published public var entries: [LargeOldFileEntry] = []
    @Published public var isScanning = false
    @Published public var config = LargeOldScanConfig()
    @Published public var sortBy: LargeOldSortField = .size
    @Published public var sortAscending = false

    // MARK: Private

    private let scanner = LargeOldScanner()
    private let mover = TrashMover()
    private var scanTask: Task<Void, Never>?

    public init() {}

    // MARK: Scanning

    public func startScan() {
        scanTask?.cancel()
        entries = []
        isScanning = true

        let cfg = config
        scanTask = Task { [weak self, scanner] in
            guard let self else { return }
            let stream = scanner.scan(config: cfg)

            for await entry in stream {
                if Task.isCancelled { break }
                await MainActor.run { [weak self] in
                    self?.entries.append(entry)
                }
            }

            if !Task.isCancelled {
                await MainActor.run { [weak self] in
                    self?.isScanning = false
                    self?.sort()
                }
            }
        }
    }

    public func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    // MARK: Computed

    public var totalSize: Int64 {
        entries.reduce(0) { $0 + $1.size }
    }

    public var selectedEntries: [LargeOldFileEntry] {
        entries.filter(\.isSelected)
    }

    public var selectedSize: Int64 {
        selectedEntries.reduce(0) { $0 + $1.size }
    }

    // MARK: Selection

    public func toggleSelection(_ id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].isSelected.toggle()
    }

    public func selectAll() {
        for i in entries.indices { entries[i].isSelected = true }
    }

    public func deselectAll() {
        for i in entries.indices { entries[i].isSelected = false }
    }

    // MARK: Sorting

    public func toggleSort(_ field: LargeOldSortField) {
        if sortBy == field {
            sortAscending.toggle()
        } else {
            sortBy = field
            sortAscending = (field == .name || field == .path)
        }
        sort()
    }

    public func sort() {
        switch sortBy {
        case .size:
            entries.sort { sortAscending ? $0.size < $1.size : $0.size > $1.size }
        case .date:
            entries.sort { sortAscending ? $0.modificationDate < $1.modificationDate : $0.modificationDate > $1.modificationDate }
        case .name:
            entries.sort { sortAscending ? $0.fileName < $1.fileName : $0.fileName > $1.fileName }
        case .path:
            entries.sort { sortAscending ? $0.path < $1.path : $0.path > $1.path }
        }
    }

    // MARK: Cleanup

    /// Moves all currently-selected files to the Trash.
    @discardableResult
    public func cleanupSelected() async -> TrashResult {
        let urls = selectedEntries.map(\.url)
        let result = await mover.moveToTrash(urls: urls)

        // Remove successfully-trashed entries.
        let trashedPaths = Set(result.snapshots.map(\.originalPath))
        entries.removeAll { trashedPaths.contains($0.path) }

        return result
    }
}