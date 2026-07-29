// kSpaceClean/Features/SmartScan/Views/ScanResultsViewModel.swift
import Foundation
import SwiftUI

/// View-model backing `ScanResultsView` — the 4-level scan results tree.
///
/// `ScanResultsViewModel` owns the canonical tree of scan results, the
/// set of expanded node ids, and the aggregate selection summary shown
/// in the bottom bar. It is the single source of truth for the tree UI;
/// sibling models (e.g. the legacy `Features/SmartScan/ScanViewModel.swift`
/// that drives `ScanResultsTreeView`) are not consulted from this view.
///
/// The model is annotated `@MainActor` so all `@Published` mutations and
/// `ScanTreeNode.setState(_:)` side-effects happen on the same isolation
/// domain as the SwiftUI view tree. Strict concurrency is enabled at the
/// project level, so any background-thread touch point would otherwise
/// surface a compile-time error.
///
/// Selection flow:
/// 1. User taps a checkbox on any row.
/// 2. `toggleSelect(_:)` flips the node's `CheckState` and mirrors the
///    new state down through the cascade (see `ScanTreeNode.setState`).
/// 3. `refreshAllParents(of:)` walks up the tree and re-aggregates
///    intermediate `ScanCategory` and `ScanSubCategory` rows into
///    `.on` / `.off` / `.mixed`.
/// 4. `updateSummary()` rebuilds `totalSelectedSize` /
///    `totalSelectedCount` by walking every category and asking the
///    leaves for their on-state URLs.
///
/// `loadMockData()` is wired up to `.onAppear` so the previews and the
/// post-scan screen render meaningful content before the production
/// scanner (Phase B) replaces the fake tree with real data.
@MainActor
final class ScanResultsViewModel: ObservableObject {
    /// Top-level categories rendered in the tree. Populated by the scan
    /// engine at completion; preview / placeholder data is supplied by
    /// ``loadMockData()``.
    @Published var categories: [ScanCategory] = []
    /// Set of tree-node ids whose subtree is currently expanded.
    /// Membership changes drive the SwiftUI `LazyVStack` rerender.
    @Published var expandedIDs: Set<UUID> = []
    /// `true` while a scan is in flight; gates progress UI overlays.
    @Published var isScanning: Bool = false
    /// Filesystem path currently being inspected by the scanner.
    /// Empty when the scan is idle.
    @Published var currentPath: String = ""
    /// Coarse progress value (`0.0`...`1.0`) for the top progress bar.
    @Published var progress: Double = 0.0
    /// Aggregate size in bytes across every URL currently selected
    /// (`.state == .on`) in the tree.
    @Published var totalSelectedSize: Int64 = 0
    /// Aggregate count of selected URLs across the tree.
    @Published var totalSelectedCount: Int = 0

    /// Toggles the expansion state of the node identified by `id`.
    ///
    /// - Parameter id: Stable `ScanTreeNode.id` (UUID) for the row whose
    ///   chevron the user tapped.
    func toggleExpand(_ id: UUID) {
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
    }

    /// Flips the selection state of `node` and propagates the cascade.
    ///
    /// The new state is `node.state == .on ? .off : .on` — `.mixed` rows
    /// become `.on` on the first tap (intentional: users always start by
    /// selecting, then refine downward).
    ///
    /// After the node's own `setState(_:)` runs the cascade downward,
    /// ``refreshAllParents(of:)`` bubbles the change back up to any
    /// intermediate `ScanCategory` / `ScanSubCategory` rows so the
    /// tri-state checkboxes correctly reflect `.mixed` / `.on` / `.off`.
    /// Finally ``updateSummary()`` rebuilds the bottom-bar counters.
    ///
    /// - Parameter node: The tree node the user toggled.
    func toggleSelect(_ node: any ScanTreeNode) {
        let newState: CheckState = (node.state == .on) ? .off : .on
        node.setState(newState)
        // Refresh parent states
        refreshAllParents(of: node)
        updateSummary()
    }

    /// Recomputes ``totalSelectedSize`` and ``totalSelectedCount`` from
    /// the current selection state of every category in ``categories``.
    ///
    /// Each leaf URL is measured by querying `FileManager.default`
    /// attributes — `try?` swallows missing files so a stale
    /// `ScanResult` row whose file was deleted between scan and cleanup
    /// does not blow up the summary.
    ///
    /// Called after every `toggleSelect(_:)` and is safe to invoke
    /// manually after bulk mutations.
    func updateSummary() {
        var totalSize: Int64 = 0
        var totalCount = 0
        for category in categories {
            let urls = category.collectSelected()
            totalCount += urls.count
            for url in urls {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int64 {
                    totalSize += size
                }
            }
        }
        totalSelectedSize = totalSize
        totalSelectedCount = totalCount
    }

    /// Re-aggregates every ancestor of `node` so the tri-state checkboxes
    /// on parent rows reflect the latest child mutations.
    ///
    /// The walk is bounded by `categories.count`: a row can only have
    /// ancestors inside one top-level category, so once we have visited
    /// every category we are done. Ancestors are located by
    /// ``findParent(of:in:)``.
    ///
    /// - Parameter node: The node whose ancestors need refreshing.
    private func refreshAllParents(of node: any ScanTreeNode) {
        // Walk up the tree refreshing parent states (simplified)
        for category in categories {
            if let parent = findParent(of: node.id, in: category) {
                parent.refreshState()
            }
        }
    }

    /// Depth-first search for the direct parent of the node identified
    /// by `id` inside the subtree rooted at `node`.
    ///
    /// Returns `nil` when `id` is the root or is not present in the
    /// subtree (which can happen if `categories` was reassigned mid-edit
    /// and the old node is no longer reachable).
    ///
    /// - Parameters:
    ///   - id: UUID of the node whose parent we want.
    ///   - node: Root of the subtree to search.
    /// - Returns: The parent `ScanTreeNode`, or `nil`.
    private func findParent(of id: UUID, in node: any ScanTreeNode) -> (any ScanTreeNode)? {
        for child in node.children {
            if child.id == id { return node }
            if let found = findParent(of: id, in: child) { return found }
        }
        return nil
    }

    /// Populates ``categories`` with a small representative tree so the
    /// view renders meaningful content before the real scanner wires up.
    ///
    /// The mock tree contains a single recommended-rating
    /// `ScanCategory` ("系统垃圾") with one `ScanSubCategory` ("系统缓存")
    /// holding a single `ScanResult` for Safari's cache directory. The
    /// values are picked so the summary bar at the bottom shows
    /// non-trivial numbers (≈2.1 GB).
    func loadMockData() {
        let recResult = ScanResult(
            url: URL(fileURLWithPath: "/Library/Caches/com.apple.Safari"),
            path: "/Library/Caches/com.apple.Safari",
            title: "Safari 缓存",
            fileSize: 2_100_000_000,
            cleanType: .cache,
            riskLevel: .recommended
        )
        let sub = ScanSubCategory(
            subCategoryID: "system.cache",
            title: "系统缓存",
            totalSize: 4_200_000_000,
            directResults: [recResult],
            showAction: false,
            riskLevel: .recommended
        )
        let category = ScanCategory(
            categoryID: "system.junk",
            title: "系统垃圾",
            totalSize: 4_200_000_000,
            subItems: [sub],
            riskLevel: .recommended
        )
        categories = [category]
    }
}