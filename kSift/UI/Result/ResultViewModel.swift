import SwiftUI
import Combine
import DetectionCore

@MainActor
final class ResultViewModel: ObservableObject {
    @Published var groups: [DuplicateGroup] = []
    @Published var selectedGroupIds: Set<UUID> = []
    @Published var activeCategory: DuplicateCategory?
    @Published var sortOrder: SortOrder = .sizeDesc
    @Published var searchText: String = ""
    // P1-1 multi-dim filters: defaults are pass-through so P0 callers and
    // tests keep their existing behavior.
    @Published var minSize: Int64 = 0
    @Published var maxSize: Int64 = .max
    @Published var dateFrom: Date?
    @Published var dateTo: Date?
    @Published var isProcessing = false
    @Published var showCleanupConfirmation = false

    /// Memoized derivation of `groups` after applying activeCategory,
    /// searchText, minSize/maxSize, dateFrom/dateTo, and sortOrder.
    ///
    /// Computed property `filteredGroups` was O(n log n) per SwiftUI body
    /// invocation, so a single search-keystroke re-sorted + re-filtered the
    /// entire result list multiple times per render pass (one per body call,
    /// plus one per GroupRowView's body). Now it's a `@Published` value
    /// rebuilt exactly once per filter-input change via CombineLatest below.
    @Published private(set) var filteredGroups: [DuplicateGroup] = []

    /// Counts of duplicate groups per category, memoized off `filteredGroups`.
    /// Drives the category chip badges and the breakdown bar.
    @Published private(set) var categoryCounts: [DuplicateCategory: Int] = [:]

    /// Counts of how many groups share each first-file basename (drives the
    /// "×N" badge in GroupRowView). Memoized off `filteredGroups` so a List
    /// with 10 000 rows doesn't rebuild this dictionary on every cell render.
    @Published private(set) var sameNameCounts: [String: Int] = [:]

    /// Strategy used to build default plans for newly selected groups.
    /// Seeded from `ProfileConfig.selectionStrategy` by the results screen.
    var defaultStrategy: SelectionStrategy = .keepNewest
    /// Scan roots passed to the planner for `.keepInsideScanRoot`.
    var scanRoots: [URL] = []

    /// Explainable keep/remove plans per selected group, built by
    /// `SelectionPlanner`. Drives the "why this copy" badges in
    /// GroupDetailView and the bottom-bar byte counter.
    @Published private(set) var selectionPlans: [UUID: SelectionPlan] = [:]
    /// File-level selection per group. Defaults to the plan's `remove`
    /// set when a group is selected; GroupDetailView mutates this so the
    /// parent list and the detail screen always agree.
    @Published private(set) var fileSelections: [UUID: Set<UUID>] = [:]
    /// Bytes staged for deletion under the current selection — memoized so
    /// the bottom action bar stays O(1) per render.
    @Published private(set) var selectedBytes: Int64 = 0
    /// Vault session of the most recent successful batch, consumed by the
    /// undo affordance (AppState.lastCleanupSession).
    @Published private(set) var lastCleanupSession: CleanupSession?
    /// Number of files currently staged for deletion across the selection.
    private(set) var stagedFileCount: Int = 0

    private var cancellables = Set<AnyCancellable>()

    enum SortOrder: String, CaseIterable {
        case sizeDesc = "Size (High→Low)"
        case sizeAsc = "Size (Low→High)"
        case countDesc = "Count (High→Low)"
        case wasteDesc = "Reclaimable (High→Low)"
        case type = "Category"
    }

    init() {
        // Rebuild filteredGroups exactly once whenever any input that feeds
        // the filter pipeline changes. IMPORTANT: the sink consumes the
        // values it RECEIVES rather than re-reading the properties —
        // @Published fires during willSet, so reading `self.activeCategory`
        // inside the sink would observe the PREVIOUS value (the filter
        // would lag one keystroke behind).
        Publishers.CombineLatest4(
            $groups, $activeCategory, $searchText, $sortOrder
        )
        .combineLatest(
            Publishers.CombineLatest4($minSize, $maxSize, $dateFrom, $dateTo)
        )
        .sink { [weak self] combined in
            guard let self else { return }
            let (groups, activeCategory, searchText, sortOrder) = combined.0
            let (minSize, maxSize, dateFrom, dateTo) = combined.1
            self.filteredGroups = Self.computeFilteredGroups(
                groups: groups,
                activeCategory: activeCategory,
                searchText: searchText,
                sortOrder: sortOrder,
                minSize: minSize,
                maxSize: maxSize,
                dateFrom: dateFrom,
                dateTo: dateTo
            )
            self.categoryCounts = Dictionary(grouping: self.filteredGroups, by: \.category)
                .mapValues(\.count)
            self.sameNameCounts = Dictionary(
                grouping: self.filteredGroups.compactMap { $0.files.first?.url.lastPathComponent },
                by: { $0 }
            ).mapValues(\.count)
        }
        .store(in: &cancellables)
    }

    /// Pure filter+sort derivation. Takes explicit inputs so it can run
    /// from the Combine sink (where properties are still one behind) and
    /// from tests with synthetic state.
    static func computeFilteredGroups(
        groups: [DuplicateGroup],
        activeCategory: DuplicateCategory?,
        searchText: String,
        sortOrder: SortOrder,
        minSize: Int64,
        maxSize: Int64,
        dateFrom: Date?,
        dateTo: Date?
    ) -> [DuplicateGroup] {
        var result = groups
        if let cat = activeCategory {
            result = result.filter { $0.category == cat }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { group in
                group.files.contains { $0.url.lastPathComponent.localizedCaseInsensitiveContains(query) }
            }
        }
        // Size range filter: keep groups whose largest file lies in
        // [minSize, maxSize]. Either bound being at its default sentinel
        // (0 / .max) is treated as "no limit on that side".
        if minSize > 0 || maxSize < Int64.max {
            let lo = minSize
            let hi = maxSize
            result = result.filter { group in
                let largest = group.files.map(\.size).max() ?? 0
                return largest >= lo && largest <= hi
            }
        }
        // Date range filter: keep groups whose newest file lies in
        // [dateFrom, dateTo]. nil on either side = unbounded.
        if dateFrom != nil || dateTo != nil {
            result = result.filter { group in
                guard let newest = group.files.map(\.modificationDate).max() else { return false }
                if let dateFrom, newest < dateFrom { return false }
                if let dateTo, newest > dateTo { return false }
                return true
            }
        }
        switch sortOrder {
        case .sizeDesc: result.sort { $0.totalSize > $1.totalSize }
        case .sizeAsc: result.sort { $0.totalSize < $1.totalSize }
        case .countDesc: result.sort { $0.files.count > $1.files.count }
        case .wasteDesc: result.sort { ($0.totalSize - ($0.files.map(\.size).max() ?? 0)) > ($1.totalSize - ($1.files.map(\.size).max() ?? 0)) }
        case .type: result.sort { $0.category.rawValue < $1.category.rawValue }
        }
        return result
    }

    /// Restores the four filter dimensions to their pass-through defaults.
    /// Called by the "Reset" button on `FilterChipsView`.
    func resetFilters() {
        minSize = 0
        maxSize = .max
        dateFrom = nil
        dateTo = nil
    }

    /// True when any of the four filter dimensions has been narrowed from
    /// its default, so the UI can offer a visible reset affordance.
    var hasActiveFilters: Bool {
        minSize > 0
            || maxSize < Int64.max
            || dateFrom != nil
            || dateTo != nil
    }

    var totalDuplicateSize: Int64 {
        groups.reduce(0) { $0 + $1.totalSize }
    }

    var totalGroupCount: Int { groups.count }

    /// Replaces the displayed groups (from a scan hand-off or a history record).
    /// Resets selection and category filter so stale state cannot leak between loads.
    func loadGroups(_ newGroups: [DuplicateGroup]) {
        groups = newGroups
        selectedGroupIds.removeAll()
        selectionPlans = [:]
        fileSelections = [:]
        selectedBytes = 0
        activeCategory = nil
        resetFilters()
    }

    /// Legacy select-all affordance. Selects every group using the default
    /// strategy — groups whose plan removes nothing (single-copy) are
    /// skipped because there is nothing to clean in them.
    func autoSelectGroups() {
        applyAutoSelect(strategy: defaultStrategy, scanRoots: scanRoots)
    }

    /// Runs `strategy` across every group and selects those whose plan
    /// actually removes copies. Each selected group gets an explainable
    /// `SelectionPlan` (shown as "why kept" badges in the detail view) and
    /// a file selection seeded from the plan's `remove` set.
    func applyAutoSelect(strategy: SelectionStrategy, scanRoots: [URL]) {
        selectionPlans = [:]
        fileSelections = [:]
        var selected: Set<UUID> = []
        var fileSel: [UUID: Set<UUID>] = [:]
        for group in groups {
            let plan = SelectionPlanner.plan(for: group, strategy: strategy, scanRoots: scanRoots)
            guard !plan.remove.isEmpty else { continue }
            selectionPlans[group.id] = plan
            selected.insert(group.id)
            fileSel[group.id] = Set(plan.remove.map(\.id))
        }
        selectedGroupIds = selected
        fileSelections = fileSel
        recomputeSelectedBytes()
    }

    /// Toggles one group in/out of the selection. Newly selected groups
    /// get a plan built under `defaultStrategy` (or reuse the one from a
    /// previous auto-select pass).
    func toggleGroup(_ groupId: UUID) {
        if selectedGroupIds.contains(groupId) {
            selectedGroupIds.remove(groupId)
            fileSelections[groupId] = nil
            selectionPlans[groupId] = nil
        } else {
            guard let group = groups.first(where: { $0.id == groupId }) else { return }
            let plan = selectionPlans[groupId]
                ?? SelectionPlanner.plan(for: group, strategy: defaultStrategy, scanRoots: scanRoots)
            guard !plan.remove.isEmpty else { return }
            selectionPlans[groupId] = plan
            fileSelections[groupId] = Set(plan.remove.map(\.id))
            selectedGroupIds.insert(groupId)
        }
        recomputeSelectedBytes()
    }

    /// Selects every filtered group (⌘A) using the default strategy.
    func selectAllGroups() {
        autoSelectGroups()
    }

    func clearSelection() {
        selectedGroupIds.removeAll()
        fileSelections = [:]
        selectionPlans = [:]
        recomputeSelectedBytes()
    }

    /// Replaces the file-level selection for one group (driven from
    /// GroupDetailView's checkbox list). Selecting files from the detail
    /// view implicitly stages the group; deselecting everything un-stages
    /// it. Keeps the group selected only if at least one file remains.
    func setFileSelection(groupId: UUID, fileIds: Set<UUID>) {
        if fileIds.isEmpty {
            selectedGroupIds.remove(groupId)
            fileSelections[groupId] = nil
            selectionPlans[groupId] = nil
        } else {
            if !selectedGroupIds.contains(groupId) {
                if let group = groups.first(where: { $0.id == groupId }) {
                    let plan = selectionPlans[groupId]
                        ?? SelectionPlanner.plan(for: group, strategy: defaultStrategy, scanRoots: scanRoots)
                    if !plan.remove.isEmpty { selectionPlans[groupId] = plan }
                }
                selectedGroupIds.insert(groupId)
            }
            fileSelections[groupId] = fileIds
        }
        recomputeSelectedBytes()
    }

    /// Installs an explicit plan for one already-selected group (driven
    /// from GroupDetailView's strategy menu). The plan's `remove` set
    /// becomes the group's staged file selection.
    func setPlan(_ plan: SelectionPlan, for groupId: UUID) {
        guard selectedGroupIds.contains(groupId) else { return }
        selectionPlans[groupId] = plan
        fileSelections[groupId] = Set(plan.remove.map(\.id))
        recomputeSelectedBytes()
    }

    /// Files currently staged for removal in `group`: the explicit file
    /// selection when one exists, otherwise the plan's remove set.
    func stagedFiles(for group: DuplicateGroup) -> [FileItem] {
        if let ids = fileSelections[group.id] {
            return group.files.filter { ids.contains($0.id) }
        }
        return selectionPlans[group.id]?.remove ?? []
    }

    private func recomputeSelectedBytes() {
        var bytes: Int64 = 0
        var count = 0
        for group in groups where selectedGroupIds.contains(group.id) {
            for file in stagedFiles(for: group) {
                let sum = bytes.addingReportingOverflow(file.size)
                bytes = sum.overflow ? Int64.max : sum.partialValue
                count += 1
            }
        }
        selectedBytes = bytes
        stagedFileCount = count
    }

    /// Trashes every file staged in the selected groups under their plans
    /// (or the keep-newest fallback for unplanned groups), returning the
    /// per-file failures the vault reported. Groups with any failure stay
    /// in the list for retry.
    @discardableResult
    func removeSelected(using manager: CleanupManager) async -> [VaultMoveFailure] {
        isProcessing = true
        defer { isProcessing = false }
        var failures: [VaultMoveFailure] = []
        var keepGroupIds: Set<UUID> = []
        var session: CleanupSession?
        let toRemove = groups.filter { selectedGroupIds.contains($0.id) }

        for group in toRemove {
            let toDelete = stagedFiles(for: group)
            guard !toDelete.isEmpty else { continue }
            do {
                let result = try await manager.moveToTrash(Array(toDelete))
                failures.append(contentsOf: result.failures)
                if result.session != nil { session = result.session }
                if !result.failures.isEmpty { keepGroupIds.insert(group.id) }
            } catch {
                // Defensive: VaultManager.moveToTrash is expected to catch
                // its own phase-2 errors and return them in `result.failures`.
                // This catch is the last-line fallback if the manager itself
                // throws (e.g. repository save failure on a successful batch).
                // Surface the error under the first file we tried to delete
                // so the UI can attribute it correctly.
                let attributedURL = toDelete.first?.url ?? group.files.first?.url
                    ?? URL(fileURLWithPath: "/")
                failures.append(VaultMoveFailure(
                    url: attributedURL,
                    reason: error.localizedDescription
                ))
                keepGroupIds.insert(group.id)
            }
        }

        groups.removeAll { selectedGroupIds.contains($0.id) && !keepGroupIds.contains($0.id) }
        selectedGroupIds.removeAll()
        fileSelections = [:]
        selectionPlans = [:]
        lastCleanupSession = session
        recomputeSelectedBytes()
        return failures
    }

    /// Removes the files staged in one group (driven from GroupDetailView's
    /// per-file selection). When the group lives in the live results list
    /// it is pruned in place: when only one copy remains the group stops
    /// being a duplicate and disappears. Groups from a history record are
    /// not part of `groups` — they clean without list mutation.
    @discardableResult
    func removeFiles(group: DuplicateGroup, using manager: CleanupManager) async -> [VaultMoveFailure] {
        let toDelete: [FileItem]
        if let ids = fileSelections[group.id] {
            toDelete = group.files.filter { ids.contains($0.id) }
        } else if let plan = selectionPlans[group.id] {
            toDelete = plan.remove
        } else {
            // History entry: nothing staged through this model — the caller
            // (GroupDetailView) handles the local-selection case itself.
            return []
        }
        guard !toDelete.isEmpty else { return [] }

        isProcessing = true
        defer { isProcessing = false }

        let result: VaultMoveResult
        do {
            result = try await manager.moveToTrash(toDelete)
            lastCleanupSession = result.session
        } catch {
            return [VaultMoveFailure(
                url: toDelete.first?.url ?? group.files.first?.url ?? URL(fileURLWithPath: "/"),
                reason: error.localizedDescription
            )]
        }

        let failedURLs = Set(result.failures.map(\.url))
        let removedURLs = Set(toDelete.map(\.url)).subtracting(failedURLs)
        let groupId = group.id
        if let idx = groups.firstIndex(where: { $0.id == groupId }) {
            let remaining = groups[idx].files.filter { !removedURLs.contains($0.url) }
            if remaining.count <= 1 {
                // A single surviving copy is no longer a duplicate — the
                // whole group leaves the results list.
                groups.remove(at: idx)
                selectedGroupIds.remove(groupId)
                fileSelections[groupId] = nil
                selectionPlans[groupId] = nil
            } else {
                let old = groups[idx]
                groups[idx] = DuplicateGroup(
                    id: old.id,
                    category: old.category,
                    totalSize: remaining.reduce(0) { $0 + $1.size },
                    fileCount: remaining.count,
                    files: remaining,
                    categoryEvidence: old.categoryEvidence,
                    similarity: old.similarity,
                    scanTimestamp: old.scanTimestamp
                )
                fileSelections[groupId] = nil
                selectedGroupIds.remove(groupId)
                selectionPlans[groupId] = nil
            }
        } else {
            // History-entry cleanup: no live list to prune, but staged
            // state must still reset for consistency.
            selectedGroupIds.remove(groupId)
            fileSelections[groupId] = nil
            selectionPlans[groupId] = nil
        }
        recomputeSelectedBytes()
        return result.failures
    }
}
