import Foundation

@MainActor
public final class PhotoCleanViewModel: ObservableObject {
    @Published public var items: [PhotoCacheItem] = []
    @Published public var isScanning = false

    private let scanner = PhotoCacheScanner()
    /// Structured-API engine (v2.0 Phase 2): photo-cache cleanup lands in
    /// the 30-day history and consumes free-tier quota.
    private(set) var engine: CleanupEngine
    public var onQuotaExhausted: (() -> Void)?

    public init(engine: CleanupEngine? = nil) {
        self.engine = engine ?? CleanupEngine.standard()
    }

    /// Re-point at the shared graph engine (v2.0 Phase 1 DI unification).
    public func useEngine(_ engine: CleanupEngine) {
        self.engine = engine
    }

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
    /// Routes through the shared cleanup engine (history + quota, v2.0).
    ///
    /// - Returns: The number of items that were successfully moved to Trash.
    @discardableResult
    public func cleanupSelected() async -> Int {
        let toRemove = selectedItems
        guard !toRemove.isEmpty else { return 0 }

        let targets = toRemove.map { item in
            CleanupTarget(url: item.url, size: item.estimatedSize, risk: .recommended)
        }
        var count = 0
        if let outcome = try? await engine.cleanup(targets: targets) {
            count = outcome.succeeded.count
            if outcome.quotaExhausted {
                onQuotaExhausted?()
            }
        }

        // Remove successfully-trashed items from the published list.
        let trashedURLs = Set(targets.prefix(count).map(\.url.path))
        items.removeAll { trashedURLs.contains($0.url.path) }

        return count
    }
}
