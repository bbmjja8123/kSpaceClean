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
        for category in snapshot.categories {
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
        var mock = snapshot
        mock.categories = [category]
        assign(snapshot: mock)
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
}