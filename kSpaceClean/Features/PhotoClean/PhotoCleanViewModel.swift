import Foundation

@MainActor
public final class PhotoCleanViewModel: ObservableObject {
    @Published public var items: [PhotoCacheItem] = []
    @Published public var isScanning = false

    private let scanner = PhotoCacheScanner()

    public init() {}

    // MARK: - Scan

    /// Runs a synchronous scan on a background queue, then publishes the
    /// results on the main actor.
    public func startScan() {
        guard !isScanning else { return }
        isScanning = true
        items = []

        Task { @MainActor in
            // Capture the sendable scanner before crossing actor boundary.
            let scanner = self.scanner
            let result = await Task.detached {
                scanner.scan()
            }.value
            self.items = result
            self.isScanning = false
        }
    }

    // MARK: - Selection

    public func toggleSelection(_ id: PhotoCacheItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isSelected.toggle()
    }

    public func selectAll() {
        for index in items.indices {
            items[index].isSelected = true
        }
    }

    public func deselectAll() {
        for index in items.indices {
            items[index].isSelected = false
        }
    }

    // MARK: - Computed

    /// Returns only the currently selected items.
    public var selectedItems: [PhotoCacheItem] {
        items.filter { $0.isSelected }
    }

    /// Total size in bytes of all selected items.
    public var selectedSize: Int64 {
        selectedItems.reduce(0) { $0 + $1.estimatedSize }
    }

    /// Items grouped by their category, with categories sorted in a
    /// consistent order.
    public var itemsByCategory: [PhotoCacheItem.PhotoCacheCategory: [PhotoCacheItem]] {
        Dictionary(grouping: items) { $0.category }
    }

    // MARK: - Cleanup

    /// Trashes all selected items and removes them from the published list.
    ///
    /// - Returns: The number of items that were successfully moved to Trash.
    @discardableResult
    public func cleanupSelected() async -> Int {
        let toRemove = selectedItems
        guard !toRemove.isEmpty else { return 0 }

        let count = await scanner.cleanup(items: toRemove)

        // Remove successfully-trashed items from the published list.
        let trashedIDs = Set(toRemove.prefix(count).map { $0.id })
        items.removeAll { trashedIDs.contains($0.id) }

        return count
    }
}
