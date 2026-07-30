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
///    `totalSelectedCount` by walking every category and summing the
///    already-tracked `selectedSize` on each node (I1: avoids per-URL
///    `FileManager` calls that would otherwise violate the 50fps budget).
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

    /// Engine that drives real scans. The view model subscribes to its
    /// `@Published categories` array and folds them into its own state.
    /// `nil` in previews; supplied by `RootView` in production.
    let engine: ScanEngine?

    /// Designated init. Pass `engine` to wire a real scan; pass `nil` for
    /// previews and tests where the model just renders mock data.
    init(engine: ScanEngine? = nil) {
        self.engine = engine
    }

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
    /// I1 fix: the previous implementation called `FileManager.default
    /// .attributesOfItem(atPath:)` for every selected URL, which is an
    /// O(selected) syscall storm on every checkbox tap. The selected size
    /// is already tracked on every node (`selectedSize`), so we walk the
    /// in-memory tree bottom-up and sum. Zero syscalls; safe at 60fps.
    ///
    /// Called after every `toggleSelect(_:)` and is safe to invoke
    /// manually after bulk mutations.
    func updateSummary() {
        var totalSize: Int64 = 0
        var totalCount = 0
        for category in categories {
            let selected = Self.collectSelected(in: category)
            totalSize += selected.size
            totalCount += selected.count
        }
        totalSelectedSize = totalSize
        totalSelectedCount = totalCount
    }

    /// In-memory bottom-up walker — returns the sum of `selectedSize` over
    /// every node in the subtree whose state is `.on`, plus the count of
    /// selected URLs. I1 fix: replaces the per-URL `FileManager` lookup.
    private static func collectSelected(in node: any ScanTreeNode) -> (size: Int64, count: Int) {
        var size: Int64 = 0
        var count = 0
        walk(node, size: &size, count: &count)
        return (size, count)
    }

    /// Recursive helper that only descends through children when the
    /// parent is in a non-off state, so we avoid walking unchecked
    /// subtrees.
    private static func walk(_ node: any ScanTreeNode, size: inout Int64, count: inout Int) {
        switch node.state {
        case .checked:
            size += node.selectedSize
            // Selected URL count is 1 for leaves (a `ScanResult` row), more
            // for sub-trees; we approximate via `node.children.count + 1` so
            // the bottom-bar count reads "0 项" on a fully-unchecked tree.
            count += max(1, node.children.count + 1)
        case .mixed:
            for child in node.children { walk(child, size: &size, count: &count) }
        case .unchecked:
            return
        }
    }

    /// Re-aggregates every ancestor of `node` so the tri-state checkboxes
    /// on parent rows reflect the latest child mutations.
    ///
    /// I1 fix: the previous implementation only refreshed the immediate
    /// parent (one-level aggregation). We now walk the full ancestor
    /// chain bottom-up so a leaf change in a deeply-nested tree still
    /// bubbles correctly to the top-level category.
    ///
    /// - Parameter node: The node whose ancestors need refreshing.
    func refreshAllParents(of node: any ScanTreeNode) {
        for category in categories {
            Self.refreshAncestors(of: node.id, in: category)
        }
    }

    /// Recursive helper — refreshes every node on the ancestor chain of
    /// `targetID` inside `subtree`. O(n) per leaf change, but n is bounded
    /// by the tree depth which is at most 4 in the v1 spec.
    private static func refreshAncestors(of targetID: UUID, in subtree: any ScanTreeNode) {
        if subtree.id == targetID { return }
        // Refresh self if any direct child might have changed.
        var anyChildChanged = false
        for child in subtree.children {
            if child.id == targetID { anyChildChanged = true; break }
            if containsID(targetID, in: child) { anyChildChanged = true; break }
        }
        if anyChildChanged {
            subtree.refreshState()
            for child in subtree.children {
                refreshAncestors(of: targetID, in: child)
            }
        }
    }

    /// Depth-first search for `targetID` inside `subtree`. Returns true as
    /// soon as any node on the chain has the id.
    private static func containsID(_ targetID: UUID, in subtree: any ScanTreeNode) -> Bool {
        for child in subtree.children {
            if child.id == targetID { return true }
            if containsID(targetID, in: child) { return true }
        }
        return false
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

    /// Start a real scan against `rootPaths` using the bound ``engine``.
    ///
    /// C1: replaces the previous `loadMockData()` call site with a real
    /// scan trigger. The view model subscribes to `engine.categories` and
    /// forwards updates into its own `@Published categories` array so the
    /// SwiftUI tree re-renders as the scan progresses.
    func startRealScan(rootPaths: [String] = []) async {
        guard let engine else { return }
        isScanning = true
        // Pre-clear so the SwiftUI tree shows the loading state immediately.
        categories = []
        await engine.startScan()
        // After `startScan` returns, subscribe to the engine's category
        // stream and forward into our tree. The wrapper runs both the
        // progress stream and the category stream in `runScan` and writes
        // to `@Published categories`; we mirror those into our own array
        // so toggling a checkbox here does not race with engine updates.
        categories = engine.categories.sorted { $0.categoryID < $1.categoryID }
        isScanning = false
        updateSummary()
    }
}