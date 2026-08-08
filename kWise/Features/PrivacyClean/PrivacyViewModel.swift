import Foundation
import SwiftUI

// MARK: - PrivacyViewModel

/// Manages the list of privacy-related items discovered by `PrivacyScanner`,
/// their selection state, and the cleanup lifecycle.
///
/// All published properties are updated on the main actor so SwiftUI views
/// can safely observe them.
@MainActor
public final class PrivacyViewModel: ObservableObject {
    @Published public var items: [PrivacyItem] = []
    @Published public var isScanning = false
    @Published public var isCleaning = false
    /// Human-readable message shown when scan or cleanup finishes.
    @Published public var statusMessage: String?

    private let scanner = PrivacyScanner()

    public init() {}

    // MARK: - Scan

    /// Starts a background scan that populates `items`.
    ///
    /// The scan runs synchronously on a detached task to avoid blocking the
    /// main actor, then publishes the results back on the main actor.
    public func startScan() {
        guard !isScanning else { return }
        isScanning = true
        items = []
        statusMessage = nil

        // Hold a local Sendable reference to avoid capturing `self` (non-Sendable)
        // across the isolation boundary of the detached task.
        let scanner = self.scanner

        Task { @MainActor in
            let results = await Task.detached {
                scanner.scan()
            }.value

            self.items = results
            self.isScanning = false

            if results.isEmpty {
                self.statusMessage = "未发现可清理的隐私数据"
            } else {
                self.statusMessage = "扫描完成，共发现 \(results.count) 项"
            }
        }
    }

    // MARK: - Selection

    public func toggleSelection(_ id: UUID) {
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

    /// The subset of items that are currently selected.
    public var selectedItems: [PrivacyItem] {
        items.filter(\.isSelected)
    }

    /// Total estimated bytes of all selected items.
    public var selectedSize: Int64 {
        selectedItems.reduce(0) { $0 + $1.estimatedSize }
    }

    /// Items grouped by category, ordered by `PrivacyCategory.displayOrder`.
    public var itemsByCategory: [(PrivacyItem.PrivacyCategory, [PrivacyItem])] {
        let dict = Dictionary(grouping: items) { $0.category }
        return PrivacyItem.PrivacyCategory.displayOrder.compactMap { category in
            guard let group = dict[category], !group.isEmpty else { return nil }
            return (category, group)
        }
    }

    // MARK: - Cleanup

    /// Moves all selected items to the Trash.
    /// - Returns: The number of items successfully cleaned.
    @discardableResult
    public func cleanupSelected() async -> Int {
        let toClean = selectedItems
        guard !toClean.isEmpty else { return 0 }

        isCleaning = true
        statusMessage = nil

        let count = await scanner.cleanup(items: toClean)

        // Remove successfully cleaned items from the published list.
        // We match by id because the `url` may already be gone after trashing.
        if count > 0 {
            let cleanedIDs = Set(toClean.prefix(count).map(\.id))
            items.removeAll { cleanedIDs.contains($0.id) }
        }

        isCleaning = false
        statusMessage = "清理完成，已移除 \(count) 项"
        return count
    }
}
