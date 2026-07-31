// kSpaceClean/Features/SmartScan/Views/ScanResultsViewModel.swift
import AppKit
import Foundation
import SwiftUI

/// The four pre-scan filters the user can tune before starting a scan.
///
/// The filters are applied **after** the orchestrator finishes, as a pure
/// transformation over the returned tree — the scan itself always walks the
/// same category definitions, so toggling a filter never changes what is
/// read from disk, only what the tree surfaces. This keeps the engine free
/// of UI-driven configuration while still giving the user a fast way to
/// narrow a noisy result set.
///
/// Defaults follow the v1 UX decision: 1 MB size floor, no age floor,
/// dangerous items hidden, and files owned by running apps hidden.
public struct ScanFilterOptions: Equatable, Sendable {
    /// Minimum file size (in bytes) for a leaf to appear in the tree.
    /// `0` disables the filter.
    public var minimumSizeBytes: Int64
    /// Only surface files that have *not* been modified for at least this
    /// many days. `0` disables the filter (surface files of any age).
    public var minimumUnusedDays: Int
    /// Hide leaves classified `.dangerous` by `RiskClassifier`.
    public var skipDangerous: Bool
    /// Hide sub-categories owned by an app that is currently running —
    /// cleaning those risks corrupting live state.
    public var skipRunningApps: Bool

    /// Memberwise init with the v1 defaults pre-filled.
    public init(
        minimumSizeBytes: Int64 = 1_048_576,
        minimumUnusedDays: Int = 0,
        skipDangerous: Bool = true,
        skipRunningApps: Bool = true
    ) {
        self.minimumSizeBytes = minimumSizeBytes
        self.minimumUnusedDays = minimumUnusedDays
        self.skipDangerous = skipDangerous
        self.skipRunningApps = skipRunningApps
    }

    /// The v1 default filter set shown on the pre-scan surface.
    public static let `default` = ScanFilterOptions()
}

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
    /// User-tunable filters shown on the pre-scan surface and applied to
    /// the engine output when a scan completes.
    @Published var filters: ScanFilterOptions = .default
    /// `false` until the first scan of this session finishes. Drives the
    /// pre-scan surface (filters + "开始扫描" CTA) versus the post-scan
    /// "nothing to clean" empty state — without it, both states collapse
    /// into `categories.isEmpty` and the user never sees a scan trigger.
    @Published private(set) var hasScanned: Bool = false

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
        let raw = engine.categories.sorted { $0.categoryID < $1.categoryID }
        categories = Self.applyFilters(raw, options: filters)
        isScanning = false
        hasScanned = true
        updateSummary()
    }

    /// Fire-and-forget scan trigger for SwiftUI button actions.
    ///
    /// The toolbar button, the ⌘N / ⌘R shortcuts, and the pre-scan CTA all
    /// route through here. Re-entrancy is guarded so a double-click cannot
    /// stack two orchestrator runs; the underlying ``ScanEngine`` would
    /// cancel the first run, but the UI would briefly flash an empty tree.
    ///
    /// - Parameter rootPaths: Optional root path override forwarded to
    ///   ``startRealScan(rootPaths:)``. Empty means "use the built-in
    ///   category definitions".
    func startScan(rootPaths: [String] = []) {
        guard !isScanning else { return }
        Task { [weak self] in
            await self?.startRealScan(rootPaths: rootPaths)
        }
    }

    // MARK: - Filtering

    /// Applies ``filters`` to a freshly-scanned tree.
    ///
    /// Pure transformation: leaves that fail the predicate are dropped and
    /// every ancestor is rebuilt with a recomputed `totalSize` so the row
    /// labels stay consistent with what is actually visible. Ancestors that
    /// end up with no surviving children are removed entirely.
    ///
    /// - Parameters:
    ///   - categories: The raw tree emitted by the scan engine.
    ///   - options: Filter set to apply.
    ///   - now: Injectable clock used for the age cutoff (tests).
    /// - Returns: A new tree containing only the surviving nodes.
    static func applyFilters(
        _ categories: [ScanCategory],
        options: ScanFilterOptions,
        now: Date = Date()
    ) -> [ScanCategory] {
        let runningBundleIDs: Set<String> = options.skipRunningApps
            ? Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            : []
        let ageCutoff: Date? = options.minimumUnusedDays > 0
            ? now.addingTimeInterval(-Double(options.minimumUnusedDays) * 86_400)
            : nil

        return categories.compactMap { category in
            let subs = category.subItems.compactMap {
                filterSubCategory($0, options: options,
                                  runningBundleIDs: runningBundleIDs,
                                  ageCutoff: ageCutoff)
            }
            guard !subs.isEmpty else { return nil }
            return ScanCategory(
                categoryID: category.categoryID,
                title: category.title,
                tooltip: category.tooltip,
                totalSize: subs.reduce(0) { $0 + $1.totalSize },
                subItems: subs,
                riskLevel: category.riskLevel,
                isRecommended: category.isRecommended
            )
        }
    }

    /// Filters one level-2 node. Returns `nil` when nothing survives (or the
    /// sub-category belongs to a running app and `skipRunningApps` is on).
    private static func filterSubCategory(
        _ sub: ScanSubCategory,
        options: ScanFilterOptions,
        runningBundleIDs: Set<String>,
        ageCutoff: Date?
    ) -> ScanSubCategory? {
        if let bundleID = sub.bundleID, runningBundleIDs.contains(bundleID) {
            return nil
        }
        let actions: [ScanAction] = sub.actions.compactMap { action in
            let results = action.results.filter {
                keep($0, options: options, ageCutoff: ageCutoff)
            }
            guard !results.isEmpty else { return nil }
            return ScanAction(
                actionID: action.actionID,
                actionType: action.actionType,
                title: action.title,
                tooltip: action.tooltip,
                totalSize: results.reduce(0) { $0 + $1.totalSize },
                results: results,
                recommend: action.recommend,
                riskLevel: action.riskLevel,
                isRecommended: action.isRecommended
            )
        }
        let direct = sub.directResults.filter {
            keep($0, options: options, ageCutoff: ageCutoff)
        }
        guard !(actions.isEmpty && direct.isEmpty) else { return nil }
        let total = actions.reduce(0) { $0 + $1.totalSize }
            + direct.reduce(0) { $0 + $1.totalSize }
        return ScanSubCategory(
            subCategoryID: sub.subCategoryID,
            title: sub.title,
            bundleID: sub.bundleID,
            appName: sub.appName,
            tooltip: sub.tooltip,
            totalSize: total,
            actions: actions,
            directResults: direct,
            showAction: sub.showAction,
            riskLevel: sub.riskLevel,
            isRecommended: sub.isRecommended
        )
    }

    /// Leaf-level predicate — size floor, age floor, and the dangerous gate.
    private static func keep(
        _ result: ScanResult,
        options: ScanFilterOptions,
        ageCutoff: Date?
    ) -> Bool {
        if result.totalSize < options.minimumSizeBytes { return false }
        if options.skipDangerous, result.riskLevel == .dangerous { return false }
        if let cutoff = ageCutoff, let modified = result.modificationDate,
           modified > cutoff {
            return false
        }
        return true
    }
}