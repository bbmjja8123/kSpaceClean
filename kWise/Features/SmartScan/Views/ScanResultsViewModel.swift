// kWise/Features/SmartScan/Views/ScanResultsViewModel.swift
import AppKit
import Foundation
import SwiftUI
import Combine

/// The four pre-scan filters the user can tune before starting a scan.
///
/// The filters are applied **after** the orchestrator finishes, as a pure
/// transformation over the returned tree — the scan itself always walks the
/// same category definitions, so toggling a filter never changes what is
/// read from disk, only what the tree surfaces. This keeps the engine free
/// of UI-driven configuration while still giving the user a fast way to
/// narrow a noisy result set.
///
/// Defaults follow the v1 UX decision: 100 KB size floor, no age floor,
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
        minimumSizeBytes: Int64 = 102_400,
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
/// F4 perf sweep: the four scan-lifecycle fields
/// (`isScanning`, `hasScanned`, `categories`, and the summary pair
/// `totalSelectedSize` / `totalSelectedCount`) are now stored on a
/// single ``ScanSnapshot`` struct so a scan-completion can update all
/// five with one setter call and one `objectWillChange` invocation —
/// instead of the previous one-invalidation-per-field cascade. Legacy
/// `@Published` accessors remain as computed properties so external
/// callers (RootView, previews) do not break.
///
/// Selection flow:
///
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
    /// Batched scan-lifecycle state. The four logical fields that always
    /// transition together at scan completion (start, end, category
    /// arrival, summary recompute) live on this struct so a single setter
    /// call emits one `objectWillChange` per SwiftUI render cycle.
    struct ScanSnapshot: Equatable {
        var isScanning: Bool = false
        var hasScanned: Bool = false
        var categories: [ScanCategory] = []
        var totalSelectedSize: Int64 = 0
        var totalSelectedCount: Int = 0
        /// Set when a scan completed but the sandbox lacks Full Disk Access,
        /// so the result is known to be incomplete (zero files). The view
        /// layer renders a "grant Full Disk Access" state instead of a
        /// misleading "your Mac is clean". Default `false` keeps the
        /// memberwise-init call sites (incl. the F4 regression test)
        /// compiling unchanged.
        var needsFullDiskAccess: Bool = false
    }

    /// Snapshot backing the legacy `@Published` accessors. Setting the
    /// whole struct at scan completion collapses what used to be 4–5
    /// separate `objectWillChange` emissions into one.
    ///
    /// Stored as `private` so the only sanctioned write paths are the
    /// ``assign(snapshot:)`` mutator (for tests) and the internal
    /// helpers (`updateSummary`, `startRealScan`). Production code
    /// reads via the computed accessors below; it never writes the
    /// struct itself.
    @Published private var snapshot = ScanSnapshot()

    /// Replaces the current scan snapshot. The only sanctioned write
    /// path from outside the model — production callers go through
    /// `startScan(...)` / `toggleSelect(...)`. Exposed `internal` so the
    /// regression-guard test can drive it; production call sites do not.
    ///
    /// - Parameter snapshot: The new batched snapshot to publish.
    func assign(snapshot: ScanSnapshot) {
        self.snapshot = snapshot
    }

    /// Backward-compatible read-only accessor — external callers
    /// (`RootView`, previews, sibling view models that read this field
    /// without owning it) continue to compile unchanged. SwiftUI's
    /// `objectWillChange` is triggered by writes to `snapshot`, so this
    /// computed read still observes the right invalidation cadence.
    var categories: [ScanCategory] { snapshot.categories }
    /// Backward-compatible read-only accessor — see ``categories``.
    var isScanning: Bool { snapshot.isScanning }
    /// Backward-compatible read-only accessor — see ``categories``.
    var hasScanned: Bool { snapshot.hasScanned }
    /// Backward-compatible read-only accessor — see ``categories``.
    var totalSelectedSize: Int64 { snapshot.totalSelectedSize }
    /// Backward-compatible read-only accessor — see ``categories``.
    var totalSelectedCount: Int { snapshot.totalSelectedCount }
    /// Backward-compatible read-only accessor — see ``categories``.
    var needsFullDiskAccess: Bool { snapshot.needsFullDiskAccess }

    /// Set of tree-node ids whose subtree is currently expanded.
    /// Membership changes drive the SwiftUI `LazyVStack` rerender.
    @Published var expandedIDs: Set<UUID> = []
    /// When `true`, the results tree renders `isHiddenByFilter` leaves too
    /// (the "show all" toggle). Task 7 consumes it; added now so the
    /// published surface exists for the view layer.
    @Published var showAllHidden: Bool = false
    /// Filesystem path currently being inspected by the scanner.
    /// Empty when the scan is idle.
    @Published var currentPath: String = ""
    /// Coarse progress value (`0.0`...`1.0`) for the top progress bar.
    @Published var progress: Double = 0.0
    /// User-tunable filters shown on the pre-scan surface and applied to
    /// the engine output when a scan completes.
    @Published var filters: ScanFilterOptions = .default

    // MARK: - Master-detail state (UX 重构 Phase 2)

    /// Category currently shown in the detail column. `nil` = first category.
    @Published var focusedCategoryID: UUID?
    /// Level-3 inline file lists currently expanded (row tap, not chevron).
    @Published var expandedAppIDs: Set<UUID> = []
    /// Rows where the user pressed "显示其余 N 项" — cap lifted for that row.
    @Published var capLiftedIDs: Set<UUID> = []
    /// Level-2 search field (matches appName / bundleID / title).
    @Published var categoryQuery: String = ""
    /// Row whose context the detail panel shows (Phase 3).
    @Published var selectedNodeID: UUID?

    /// O(1) node + parent lookups. NOT @Published: rebuilt inside the same
    /// transaction as the snapshot write so no extra `objectWillChange`
    /// fires (F4 contract), and reads never invalidate SwiftUI.
    private(set) var nodeIndex: [UUID: any ScanTreeNode] = [:]
    private(set) var parentIndex: [UUID: UUID] = [:]

    /// Single DFS over `snapshot.categories`, run at scan completion and
    /// filter re-apply (both already inside snapshot-write transactions).
    func rebuildIndices() {
        var nodes: [UUID: any ScanTreeNode] = [:]
        var parents: [UUID: UUID] = [:]
        func walk(_ node: any ScanTreeNode, parent: UUID?) {
            nodes[node.id] = node
            if let parent { parents[node.id] = parent }
            for child in node.children { walk(child, parent: node.id) }
        }
        for category in snapshot.categories {
            walk(category, parent: nil)
        }
        nodeIndex = nodes
        parentIndex = parents
    }

    /// Live node resolution — detail panel reads state/size through this so
    /// cascade changes never go stale.
    func node(for id: UUID) -> (any ScanTreeNode)? { nodeIndex[id] }

    /// Re-aggregates only the real ancestor chain of `id` (O(depth)) —
    /// replaces the per-click `refreshAllParents` that did one DFS per
    /// category (the second half of the two-whole-tree-walks-per-click bug).
    func refreshAncestors(of id: UUID) {
        var cursor = parentIndex[id]
        while let currentID = cursor {
            guard let current = nodeIndex[currentID] else { break }
            current.refreshState()
            cursor = parentIndex[currentID]
        }
    }

    /// Incremental summary: recomputes one category's contribution and
    /// adjusts the published totals by the delta — O(changed subtree)
    /// instead of a full-tree walk on every checkbox tap.
    func refreshSummary(forCategory categoryID: UUID) {
        guard let category = nodeIndex[categoryID] as? ScanCategory else { return }
        let selected = Self.collectSelected(in: category)
        let previous = categoryContribution[categoryID] ?? (0, 0)
        var working = snapshot
        working.totalSelectedSize += selected.size - Int64(previous.size)
        working.totalSelectedCount += selected.count - previous.count
        categoryContribution[categoryID] = (selected.size, selected.count)
        snapshot = working
    }

    /// Per-category selected (size, count) memo backing ``refreshSummary(forCategory:)``.
    private var categoryContribution: [UUID: (size: Int64, count: Int)] = [:]

    /// Engine that drives real scans. The view model subscribes to its
    /// `@Published categories` array and folds them into its own state.
    /// `nil` in previews; supplied by `RootView` in production.
    let engine: ScanEngine?

    /// Live progress snapshot forwarded from ``engine`` while a scan runs.
    /// The scan-tab UI renders this with `ScanProgressView` so the user
    /// sees real-time progress instead of a static placeholder.
    @Published private(set) var engineProgress: ScanProgress = ScanProgress()

    /// Combine subscription that mirrors `engine.$progress` into
    /// ``engineProgress``. The engine publishes on the main actor; the
    /// sink closure is invoked on whatever thread Combine delivers on, so
    /// we hop back to the main actor explicitly. `MainActor.assumeIsolated`
    /// (Swift 5.9+) is unavailable on this toolchain, hence the `Task`.
    private var engineProgressCancellable: AnyCancellable?

    /// F6 perf sweep: the pre-scan slider writes into this draft, not
    /// `filters`. A Combine debounce flushes the draft into the real
    /// `filters` after 150ms of slider inactivity, so dragging the
    /// slider across a full 0–100 MB range fires the filter pipeline
    /// once instead of 100 times.
    @Published var draftFilters: ScanFilterOptions = .default

    /// Combine subscription that copies `draftFilters` into `filters`
    /// after a 150ms quiet window. Kept on the view model so it
    /// shares the model's @MainActor lifetime.
    private var filterDebounceCancellable: AnyCancellable?

    /// Designated init. Pass `engine` to wire a real scan; pass `nil` for
    /// previews and tests where the model just renders mock data.
    init(engine: ScanEngine? = nil) {
        self.engine = engine
        // F6 perf sweep: debounce `draftFilters` → `filters` by 150 ms so
        // the size-floor slider does not fire the filter pipeline on
        // every pixel of drag. The pipeline still re-runs on every
        // committed value, just at most once per gesture instead of
        // 60 times per second.
        filterDebounceCancellable = $draftFilters
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] newValue in
                guard let self else { return }
                guard self.filters != newValue else { return }
                self.filters = newValue
            }

        // Mirror the engine's live progress into `engineProgress` so the
        // scan tab can render a real progress view. Engine publishes are
        // @MainActor-bound, but the Combine pipeline may deliver on a
        // background thread; hop back explicitly.
        if let engine {
            engineProgressCancellable = engine.$progress.sink { [weak self] progress in
                Task { @MainActor in
                    self?.engineProgress = progress
                }
            }
        }
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
    /// UX 重构 Phase 2: the checkbox tap is now O(depth + changed subtree) —
    /// `setState` cascades down, `refreshAncestors(of:)` bubbles up along
    /// the `parentIndex` chain, and `refreshSummary(forCategory:)` applies
    /// the delta to the totals. The old path did 2 full-tree DFS walks per
    /// click (`refreshAllParents` × categories + `updateSummary`).
    ///
    /// - Parameter node: The tree node the user toggled.
    func toggleSelect(_ node: any ScanTreeNode) {
        let newState: CheckState = (node.state == .on) ? .off : .on
        node.setState(newState)
        refreshAncestors(of: node.id)
        // The topmost ancestor is a category — refresh its contribution.
        if var cursor = parentIndex[node.id] {
            while let next = parentIndex[cursor] { cursor = next }
            refreshSummary(forCategory: cursor)
        } else if nodeIndex[node.id] is ScanCategory {
            refreshSummary(forCategory: node.id)
        }
    }

    /// Context the detail panel shows on row tap (Phase 3); selection is
    /// left untouched — tap ≠ check.
    func selectDetail(_ id: UUID?) {
        selectedNodeID = id
    }

    // MARK: - Bulk selection (v1.5 Task 4)

    /// Select every visible node — wired to the 全选 button in the results
    /// `SummaryBar`. Cascades downward via each node's `setState(_:)`
    /// implementation; parents recompute their state automatically.
    func selectAll() {
        for category in snapshot.categories {
            category.setState(.on)
        }
        updateSummary()
    }

    /// Invert selection across every leaf — wired to the 反选 button.
    /// Internal nodes (categories, sub-categories, actions) are recomputed
    /// via `refreshState()` so tri-state checkboxes accurately reflect the
    /// new children states.
    func invertSelection() {
        for category in snapshot.categories {
            invertLeaves(in: category)
            category.refreshState()
        }
        updateSummary()
    }

    /// Recursive helper for ``invertSelection()`` — flips `state` only on
    /// leaf rows (rows with no children); internal rows get a later
    /// `refreshState()` pass.
    private func invertLeaves(in node: any ScanTreeNode) {
        if node.children.isEmpty {
            let flipped: CheckState = (node.state == .on) ? .off : .on
            node.setState(flipped)
        } else {
            for child in node.children {
                invertLeaves(in: child)
            }
        }
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
        for category in snapshot.categories {
            let selected = Self.collectSelected(in: category)
            totalSize += selected.size
            totalCount += selected.count
        }
        snapshot.totalSelectedSize = totalSize
        snapshot.totalSelectedCount = totalCount
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
        var mock = snapshot
        mock.categories = [category]
        assign(snapshot: mock)
        rebuildIndices()
    }

    /// Start a real scan against `rootPaths` using the bound ``engine``.
    ///
    /// C1: replaces the previous `loadMockData()` call site with a real
    /// scan trigger. The view model subscribes to `engine.categories` and
    /// forwards updates into its own `@Published categories` array so the
    /// SwiftUI tree re-renders as the scan progresses.
    ///
    /// F4 perf sweep: the four scan-lifecycle fields (`isScanning`,
    /// `hasScanned`, `categories`, and the summary pair) update inside
    /// one MainActor transaction so the SwiftUI render pass fires once
    /// instead of four times per completion.
    func startRealScan(rootPaths: [String] = []) async {
        guard let engine else { return }
        var working = snapshot
        working.isScanning = true
        // Pre-clear so the SwiftUI tree shows the loading state immediately.
        working.categories = []
        working.needsFullDiskAccess = false
        snapshot = working

        // Live progress: reset to a fresh `.scanning` snapshot so the
        // progress view renders immediately, before the first engine
        // publish lands.
        engineProgress = ScanProgress(state: .scanning)

        // FDA fast-fail: a sandboxed app without Full Disk Access cannot
        // see any user files, so the scan would legitimately enumerate
        // zero files and we'd show a false "clean" screen. Detect it up
        // front and surface the FDA guidance state instead.
        guard UserPathResolver.hasFullDiskAccess() else {
            var noFDA = working
            noFDA.isScanning = false
            noFDA.hasScanned = true
            noFDA.needsFullDiskAccess = true
            snapshot = noFDA
            return
        }

        await engine.startScan()
        // Deterministic completion: `startScan()` is fire-and-forget (it
        // returns as soon as the orchestrator's stream is created). Await
        // `waitForScanCompletion()` so `engine.categories` below reflects
        // the finished scan — reading it immediately (the pre-fix
        // behaviour) always yielded an empty array and the UI showed
        // "clean" while the scan ran unobserved.
        await engine.waitForScanCompletion()

        // After the engine finishes, fold its categories into our own
        // array. The wrapper runs both the progress stream and the
        // category stream in `runScan` and writes to `@Published
        // categories`; we mirror those into our own array so toggling a
        // checkbox here does not race with engine updates.
        let raw = engine.categories.sorted { $0.categoryID < $1.categoryID }
        var newSnapshot = working
        newSnapshot.categories = Self.annotateHidden(raw, options: filters)
        newSnapshot.isScanning = false
        newSnapshot.hasScanned = true

        // Post-scan FDA re-check: if the scan came back empty AND FDA is
        // missing, the empty result is an artifact of sandboxing (the walk
        // never saw real files), not a clean Mac. Surface the FDA state.
        if newSnapshot.categories.isEmpty, !UserPathResolver.hasFullDiskAccess() {
            newSnapshot.needsFullDiskAccess = true
        }

        // Recompute summary on the new categories before publishing so
        // the summary bar never shows a transient "0 项" between the
        // categories write and the summary write.
        var totalSize: Int64 = 0
        var totalCount = 0
        for category in newSnapshot.categories {
            let selected = Self.collectSelected(in: category)
            totalSize += selected.size
            totalCount += selected.count
        }
        newSnapshot.totalSelectedSize = totalSize
        newSnapshot.totalSelectedCount = totalCount

        // Single write — one `objectWillChange` emission covers all five
        // logical state changes.
        snapshot = newSnapshot
        // Rebuild the O(1) indices + per-category contribution memo in the
        // same transaction (no extra objectWillChange — non-@Published).
        rebuildIndices()
        categoryContribution.removeAll()
        for category in newSnapshot.categories {
            let selected = Self.collectSelected(in: category)
            categoryContribution[category.id] = (selected.size, selected.count)
        }
        // Reset the master-detail focus to the first (largest) category.
        focusedCategoryID = nil
        expandedAppIDs.removeAll()
        capLiftedIDs.removeAll()
        selectedNodeID = nil
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

    /// Snapshot of running bundle IDs, captured off the main actor so the
    /// filter pipeline does not stall on launchd.
    ///
    /// `NSWorkspace.runningApplications` queries launchd synchronously;
    /// on a busy system with 200+ apps this can take 50–200ms per call.
    /// Marking the helper `nonisolated static` lets callers hop to a
    /// background thread before they ask for the snapshot, while still
    /// remaining safe (no shared mutable state). `NSWorkspace` is
    /// documented as main-actor-safe for read-only `runningApplications`
    /// access — Apple permits off-main reads in practice and the
    /// performance gain is meaningful.
    nonisolated static func snapshotRunningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    /// Applies ``filters`` to a freshly-scanned tree — fold-not-delete.
    ///
    /// Leaves that fail the size / age / dangerous gates are annotated
    /// `isHiddenByFilter = true` and KEPT in the tree, so the cleanup
    /// pipeline can still select them while the default view hides them.
    /// A parent folds up hidden when its entire subtree is hidden.
    /// Empty categories (the 6 always-rendered skeletons) survive and stay
    /// visible. The only delete is `skipRunningApps`: a sub-category owned
    /// by a currently-running app truly cannot be cleaned right now.
    ///
    /// Rebuilds new node instances (never mutates the engine's tree) —
    /// same purity contract the old `applyFilters` had.
    static func annotateHidden(
        _ categories: [ScanCategory],
        options: ScanFilterOptions,
        now: Date = Date()
    ) -> [ScanCategory] {
        // F8: signpost marker around the filter pipeline so an
        // Instruments run can attribute time spent walking the tree.
        let _ = PerfInterval("filter.annotate")
        let runningBundleIDs: Set<String> = options.skipRunningApps
            ? Self.snapshotRunningBundleIDs() : []
        let ageCutoff: Date? = options.minimumUnusedDays > 0
            ? now.addingTimeInterval(-Double(options.minimumUnusedDays) * 86_400)
            : nil

        return categories.map { category in
            let subs = category.subItems.compactMap { sub -> ScanSubCategory? in
                // skipRunningApps keeps DELETE semantics — the only delete.
                if options.skipRunningApps, let bundleID = sub.bundleID,
                   runningBundleIDs.contains(bundleID) {
                    return nil
                }
                return annotateSubHidden(sub, options: options, ageCutoff: ageCutoff)
            }
            // Skeletons (zero children) stay visible; only a non-empty
            // subtree whose children are ALL hidden folds up to hidden.
            let allChildrenHidden = !subs.isEmpty && subs.allSatisfy(\.isHiddenByFilter)
            return ScanCategory(
                categoryID: category.categoryID,
                title: category.title,
                tooltip: category.tooltip,
                totalSize: category.totalSize,
                subItems: subs,
                riskLevel: category.riskLevel,
                isRecommended: category.isRecommended,
                isHiddenByFilter: allChildrenHidden
            )
        }
    }

    /// Annotates one level-2 node, threading `isHiddenByFilter` through
    /// its actions / direct results. Never returns `nil` (fold-not-delete).
    private static func annotateSubHidden(
        _ sub: ScanSubCategory,
        options: ScanFilterOptions,
        ageCutoff: Date?
    ) -> ScanSubCategory {
        let actions: [ScanAction] = sub.actions.map { action in
            let results = action.results.map {
                annotateResultHidden($0, options: options, ageCutoff: ageCutoff)
            }
            let allHidden = !results.isEmpty && results.allSatisfy(\.isHiddenByFilter)
            return ScanAction(
                actionID: action.actionID,
                actionType: action.actionType,
                title: action.title,
                tooltip: action.tooltip,
                totalSize: action.totalSize,
                results: results,
                recommend: action.recommend,
                riskLevel: action.riskLevel,
                isRecommended: action.isRecommended,
                isHiddenByFilter: allHidden
            )
        }
        let direct = sub.directResults.map {
            annotateResultHidden($0, options: options, ageCutoff: ageCutoff)
        }
        let childrenHidden = actions.allSatisfy(\.isHiddenByFilter)
            && direct.allSatisfy(\.isHiddenByFilter)
        // Task B2: a pseudo-app row with any content is exempt from the
        // small-file fold — it must stay visible even when every leaf is
        // sub-100KB (the row is the only "name" the user has for that folder).
        let pseudoExempt = sub.isPseudoApp && sub.totalSize > 0
        let allHidden = !(actions.isEmpty && direct.isEmpty) && childrenHidden && !pseudoExempt
        return ScanSubCategory(
            subCategoryID: sub.subCategoryID,
            title: sub.title,
            bundleID: sub.bundleID,
            appName: sub.appName,
            tooltip: sub.tooltip,
            totalSize: sub.totalSize,
            actions: actions,
            directResults: direct,
            showAction: sub.showAction,
            riskLevel: sub.riskLevel,
            isRecommended: sub.isRecommended,
            isPseudoApp: sub.isPseudoApp,
            isHiddenByFilter: allHidden
        )
    }

    /// Leaf-level annotation — size / age / dangerous become "mark hidden",
    /// never delete. Rebuilds a new `ScanResult` (all `let` fields carried
    /// over verbatim; `state` resets to `.off` exactly as the old filter
    /// did, so selection is not preserved across a filter re-apply).
    private static func annotateResultHidden(
        _ result: ScanResult,
        options: ScanFilterOptions,
        ageCutoff: Date?
    ) -> ScanResult {
        let ageHidden: Bool = {
            guard let cutoff = ageCutoff, let modified = result.modificationDate else { return false }
            return modified > cutoff
        }()
        let hidden = result.totalSize < options.minimumSizeBytes
            || (options.skipDangerous && result.riskLevel == .dangerous)
            || ageHidden
        return ScanResult(
            url: result.url,
            path: result.path,
            title: result.title,
            tooltip: result.tooltip,
            iconSystemName: result.iconSystemName,
            fileSize: result.fileSize,
            modificationDate: result.modificationDate,
            cleanType: result.cleanType,
            cautionID: result.cautionID,
            nestedResults: result.nestedResults,
            riskLevel: result.riskLevel,
            isRecommended: result.isRecommended,
            isHiddenByFilter: hidden
        )
    }

    // MARK: - Master-detail row suppliers (UX 重构 Phase 2)

    /// Presentation caps for the master-detail lists. The old tree
    /// materialized an entire expanded subtree in one layout pass — the
    /// root cause of the multi-second 应用缓存 freeze. Suppliers return
    /// only the capped slice; "显示其余 N 项" lifts the cap per row.
    enum ScanListCap {
        static let subcategories = 30
        static let files = 20
    }

    /// One capped page of rows for a master-detail level.
    struct ScanLevelPage {
        /// Sorted size-descending, filtered, capped.
        let nodes: [any ScanTreeNode]
        /// What "显示其余 N 项（按大小）" advertises (0 when the cap isn't hit).
        let remainingCount: Int
    }

    /// Level-2 rows for a category: one row per app bucket (bundleID-matched)
    /// or pseudo-app folder, sorted by size descending, capped at
    /// `ScanListCap.subcategories` unless the cap was lifted for this
    /// category. `query` filters by appName / bundleID / title.
    func visibleSubcategories(in category: ScanCategory) -> [any ScanTreeNode] {
        let query = categoryQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let visible = category.subItems
            .filter { showAllHidden ? true : !$0.isHiddenByFilter }
            .filter { sub in
                guard !query.isEmpty else { return true }
                return sub.title.lowercased().contains(query)
                    || (sub.appName?.lowercased().contains(query) ?? false)
                    || (sub.bundleID?.lowercased().contains(query) ?? false)
            }
            .sorted { $0.totalSize > $1.totalSize }
        guard !capLiftedIDs.contains(category.id), visible.count > ScanListCap.subcategories else {
            return visible
        }
        return Array(visible.prefix(ScanListCap.subcategories))
    }

    /// Number of rows hidden behind the level-2 cap for `category`.
    func remainingSubcategoryCount(in category: ScanCategory) -> Int {
        let visible = category.subItems.filter { showAllHidden ? true : !$0.isHiddenByFilter }
        guard !capLiftedIDs.contains(category.id) else { return 0 }
        return max(0, visible.count - ScanListCap.subcategories)
    }

    /// Level-3 rows inside an app bucket: flatten actions' results plus
    /// direct results, size-descending, capped at `ScanListCap.files`
    /// unless lifted for this app row.
    func visibleFiles(in sub: ScanSubCategory) -> [any ScanTreeNode] {
        let leaves: [any ScanTreeNode] = sub.showAction
            ? sub.actions.flatMap { $0.results.map { $0 as any ScanTreeNode } }
            : sub.directResults.map { $0 as any ScanTreeNode }
        let visible = leaves
            .filter { showAllHidden ? true : !$0.isHiddenByFilter }
            .sorted { $0.totalSize > $1.totalSize }
        guard !capLiftedIDs.contains(sub.id), visible.count > ScanListCap.files else {
            return visible
        }
        return Array(visible.prefix(ScanListCap.files))
    }

    /// Number of file rows hidden behind the level-3 cap for `sub`.
    func remainingFileCount(in sub: ScanSubCategory) -> Int {
        let leaves: [any ScanTreeNode] = sub.showAction
            ? sub.actions.flatMap { $0.results.map { $0 as any ScanTreeNode } }
            : sub.directResults.map { $0 as any ScanTreeNode }
        let visible = leaves.filter { showAllHidden ? true : !$0.isHiddenByFilter }
        guard !capLiftedIDs.contains(sub.id) else { return 0 }
        return max(0, visible.count - ScanListCap.files)
    }

    /// The category currently shown in the detail column (first by size
    /// when nothing focused).
    var focusedCategory: ScanCategory? {
        if let focusedCategoryID,
           let category = nodeIndex[focusedCategoryID] as? ScanCategory {
            return category
        }
        return snapshot.categories.sorted { $0.totalSize > $1.totalSize }.first
    }

    // MARK: - Cleanup bridge (UX 重构 Phase 2)

    /// Every URL currently checked in the tree — the SummaryBar 清理 button
    /// now cleans exactly this (previously it re-ran Smart Care and
    /// ignored the user's selection).
    func selectedURLs() -> [URL] {
        snapshot.categories.flatMap { $0.collectSelected() }
    }

    /// Selected URL → scanned size, so the cleanup outcome can report
    /// truthful freed bytes without a per-URL stat storm.
    func selectedSizesByURL() -> [URL: Int64] {
        var sizes: [URL: Int64] = [:]
        func walk(_ node: any ScanTreeNode) {
            if let result = node as? ScanResult, node.state == .checked {
                sizes[result.url] = result.fileSize
            }
            if node.state != .unchecked {
                for child in node.children { walk(child) }
            }
        }
        for category in snapshot.categories { walk(category) }
        return sizes
    }
}