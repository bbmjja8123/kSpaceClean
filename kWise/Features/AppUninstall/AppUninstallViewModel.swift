import Foundation
import Combine
import AppCatalogCore

// MARK: - ViewModel

@MainActor
public final class AppUninstallViewModel: ObservableObject {
    @Published public var entries: [UninstallAppEntry] = []
    @Published public var isScanning = false
    @Published public var sortBy: SortField = .name
    @Published public var sortAscending = true

    public enum SortField: String, CaseIterable, Sendable {
        case name
        case size
        case leftoverSize
        case lastUsed
        case installDate

        public var displayName: String {
            switch self {
            case .name: return "名称"
            case .size: return "总大小"
            case .leftoverSize: return "残留大小"
            case .lastUsed: return "未使用优先"
            case .installDate: return "最近安装"
            }
        }
    }

    /// Search by app name or bundle ID (v2.3 Phase 4).
    @Published public var searchText: String = ""

    /// 拖入 .app 即扫 (v2.6, AppCleaner 标志交互)：检测交给 scanner，
    /// 已在列表中则激活既有条目。
    public func importDraggedApp(at appURL: URL) async {
        guard appURL.pathExtension.lowercased() == "app" else { return }
        if let existing = entries.first(where: {
            $0.appURL.standardizedFileURL == appURL.standardizedFileURL
        }) {
            entries = entries.map { $0.appURL == appURL ? existing : $0 }
            return
        }
        isScanning = true
        let entry = await scanner.scanDraggedApp(at: appURL)
        if let entry {
            entries.append(entry)
        }
        isScanning = false
    }

    /// 共享组件警告 (v2.6, Lemon 负分思想)：残留路径与其他已安装 App 的
    /// 路径共享同一父目录 → 该目录可能是公共组件，删除影响别家。
    func sharedComponentWarning(for entry: UninstallAppEntry) -> String? {
        let otherDirs = Set(entries.filter { $0.bundleID != entry.bundleID }
            .flatMap { $0.residues.map { $0.url.deletingLastPathComponent().path } })
        let shared = entry.residues.filter {
            otherDirs.contains($0.url.deletingLastPathComponent().path)
        }
        guard !shared.isEmpty else { return nil }
        let names = shared.prefix(3).map { $0.url.lastPathComponent }.joined(separator: "、")
        return "\(shared.count) 个残留位于与其他应用共享的目录（\(names)…），删除可能影响其他应用。"
    }

    /// App Reset (v2.6)：保留 App，清偏好/缓存。
    public func resetApp(_ entry: UninstallAppEntry) async throws {
        try await scanner.reset(entry: entry)
    }
    /// Filter by catalog source (用户安装 / App Store / Homebrew / Setapp).
    @Published public var sourceFilter: AppSource?

    /// Filtered + sorted entries backing the list.
    public var visibleEntries: [UninstallAppEntry] {
        var items = entries
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            items = items.filter {
                $0.appName.lowercased().contains(query)
                    || $0.bundleID.lowercased().contains(query)
            }
        }
        if let sourceFilter {
            items = items.filter { $0.source == sourceFilter }
        }
        items = sorted(items)
        // 未使用优先：lastUsed 旧者在前；未知排尾并显示「未知」。
        if sortBy == .lastUsed {
            items.sort { a, b in
                switch (a.lastUsedDate, b.lastUsedDate) {
                case let (l?, r?): return l < r
                case (.some, .none): return true
                case (.none, .some): return false
                default: return a.appName < b.appName
                }
            }
        }
        return items
    }

    private let scanner = AppUninstallScanner()
    /// Structured-API engine (v2.0 Phase 2). Uninstalls route through
    /// `CleanupEngine.cleanup(targets:)` so every app removal lands in the
    /// 30-day history, is restorable, and consumes free-tier quota. The app
    /// root re-points this at the shared graph engine.
    private(set) var engine: CleanupEngine
    /// Invoked when a run leaves leftovers behind because the free quota
    /// was exhausted — the root presents the paywall.
    public var onQuotaExhausted: (() -> Void)?

    public init(engine: CleanupEngine? = nil) {
        self.engine = engine ?? CleanupEngine.standard()
    }

    /// Re-point at the shared graph engine (v2.0 Phase 1 DI unification).
    public func useEngine(_ engine: CleanupEngine) {
        self.engine = engine
    }

    // MARK: - Scanning

    public func startScan() {
        guard !isScanning else { return }
        isScanning = true
        entries = []

        Task {
            var result = await self.scanner.scan()
            // 孤儿残留 (v2.4)：App 本体已删、残留仍在。默认不选。
            let orphans = await self.scanner.scanOrphans()
            result.append(contentsOf: orphans)
            self.entries = self.sorted(result)
            self.isScanning = false
        }
    }

    // MARK: - Detail Panel (v2.6 Task 4)

    /// 双栏右侧面板当前展示的条目（AppRow 点击设置）。
    @Published public var selectedEntryID: UUID?

    /// 面板内残留勾选状态，按条目隔离（key = entry id，value = 勾选的残留路径）。
    @Published public var selectedResiduePaths: [UUID: Set<String>] = [:]

    /// 分组惰性缓存（key = entry id）。分组在后台线程计算、主线程发布。
    @Published public private(set) var groupedResidues: [UUID: [ResidueGroup]] = [:]

    /// NLEmbedding 解析后仍为 nil → 面板显示降级提示行
    /// （未知路径全落 other，规则遍结果仍可信）。与分组结果同步发布。
    public private(set) var groupingDegraded = false

    /// 分组计算进行中的条目（防重复派发 + 「分析中…」骨架数据源）。
    @Published public private(set) var isGrouping = false

    private var groupingInFlight: Set<UUID> = []

    /// 面板当前条目（`selectedEntryID` 失效后自动回 nil → 面板空态）。
    public var selectedEntry: UninstallAppEntry? {
        guard let selectedEntryID else { return nil }
        return entries.first { $0.id == selectedEntryID }
    }

    /// 面板里是否出现过任何显式残留勾选（spec §7 提交语义消歧）：
    /// 有 → 提交 App 本体 + 仅选中的残留；无 → 整 App 语义（本体 + 全部残留）。
    /// 全局判定而非按选中条目 —— 勾选状态按条目隔离，任一条目出现过
    /// 显式勾选即进入明细模式，清空后回退整 App 语义。
    public var hasExplicitResidueSelection: Bool {
        selectedResiduePaths.contains { !$0.value.isEmpty }
    }

    /// 面板残留行勾选切换（按条目隔离，互不影响其他条目）。
    public func toggleResidue(entryID: UUID, path: String) {
        var set = selectedResiduePaths[entryID] ?? []
        if set.contains(path) { set.remove(path) } else { set.insert(path) }
        selectedResiduePaths[entryID] = set
    }

    /// 组级级联勾选：组内全部残留一起选中 / 取消（单项仍可反调）。
    public func setGroupSelection(entryID: UUID, residues: [ResidueFile], selected: Bool) {
        let paths = Set(residues.map { $0.url.path })
        var set = selectedResiduePaths[entryID] ?? []
        if selected { set.formUnion(paths) } else { set.subtract(paths) }
        selectedResiduePaths[entryID] = set
    }

    /// 选中条目的分组（惰性计算：命中缓存直接返回；否则后台分组 +
    /// 主线程发布）。未命中时返回 nil，面板显示「分析中…」骨架。
    ///
    /// 分组引擎为同步纯计算（NSCache 线程安全），放在 detached Task
    /// 中避免阻塞主线程；结果经 `MainActor.run` 发布以满足
    /// SWIFT_STRICT_CONCURRENCY=complete。
    public func groupedResiduesForSelectedEntry() -> [ResidueGroup]? {
        guard let entry = selectedEntry else { return nil }
        if let cached = groupedResidues[entry.id] { return cached }
        guard !groupingInFlight.contains(entry.id) else { return nil }
        groupingInFlight.insert(entry.id)

        let residues = entry.residues
        let entryID = entry.id
        // 本方法在 body 求值期间被调用 —— `@Published` 变更必须推迟到
        // 下一 runloop 发布，否则触发 "Publishing changes from within
        // view updates" 运行时警告。
        Task { @MainActor in self.isGrouping = true }
        Task.detached(priority: .userInitiated) {
            let embedding = ResidueGroupingEngine.resolveEmbedding(nil)
            let degraded = (embedding == nil)
            let groups = ResidueGroupingEngine.group(residues, embedding: embedding)
            await MainActor.run {
                self.groupedResidues[entryID] = groups
                self.groupingDegraded = degraded
                self.groupingInFlight.remove(entryID)
                self.isGrouping = !self.groupingInFlight.isEmpty
            }
        }
        return nil
    }

    // MARK: - Selection

    public func toggleSelection(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isSelected.toggle()
    }

    public func selectAll() {
        for index in entries.indices {
            entries[index].isSelected = true
        }
    }

    public func deselectAll() {
        for index in entries.indices {
            entries[index].isSelected = false
        }
    }

    /// Entries currently marked for uninstall, sorted by total size descending.
    public var selectedEntries: [UninstallAppEntry] {
        entries.filter(\.isSelected).sorted { $0.totalSize > $1.totalSize }
    }

    /// Total reclaimable space from all selected entries.
    public var selectedSize: Int64 {
        selectedEntries.reduce(0) { $0 + $1.totalSize }
    }

    /// Number of entries that have at least one leftover file.
    public var appsWithLeftovers: Int {
        entries.filter { $0.leftoverSize > 0 }.count
    }

    // MARK: - Sorting

    public func toggleSort(_ field: SortField) {
        if sortBy == field {
            sortAscending.toggle()
        } else {
            sortBy = field
            sortAscending = field == .name // default ascending for name, descending for sizes
        }
        entries = sorted(entries)
    }

    private func sorted(_ items: [UninstallAppEntry]) -> [UninstallAppEntry] {
        switch sortBy {
        case .name:
            return sortAscending
                ? items.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
                : items.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedDescending }
        case .size:
            return sortAscending
                ? items.sorted { $0.totalSize < $1.totalSize }
                : items.sorted { $0.totalSize > $1.totalSize }
        case .leftoverSize:
            return sortAscending
                ? items.sorted { $0.leftoverSize < $1.leftoverSize }
                : items.sorted { $0.leftoverSize > $1.leftoverSize }
        case .lastUsed:
            return items  // handled by visibleEntries (unknown-last policy)
        case .installDate:
            return sortAscending
                ? items.sorted { ($0.installDate ?? .distantPast) < ($1.installDate ?? .distantPast) }
                : items.sorted { ($0.installDate ?? .distantPast) > ($1.installDate ?? .distantPast) }
        }
    }

    // MARK: - Uninstall

    /// Uninstalls all currently selected entries.
    /// - Returns: A tuple of succeeded app names and failed app names.
    public func uninstallSelected() async -> (succeeded: [String], failed: [String]) {
        let targets = selectedEntries
        guard !targets.isEmpty else { return ([], []) }

        var succeeded: [String] = []
        var failed: [String] = []

        for entry in targets {
            // App bundle + every located leftover become one CleanupTarget
            // set, so a single `CleanupEngine` run records restorable
            // history rows and consumes quota (v2.0 Phase 2).
            let urls = ([entry.appURL] + entry.leftoverURLs)
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            let engineTargets = urls.map { url in
                CleanupTarget(
                    url: url,
                    size: Self.sizeOf(url),
                    risk: .caution,
                    bundleID: entry.bundleID
                )
            }
            do {
                let outcome = try await engine.cleanup(targets: engineTargets)
                if outcome.failed.isEmpty {
                    succeeded.append(entry.appName)
                } else {
                    failed.append(entry.appName)
                }
                if outcome.quotaExhausted {
                    onQuotaExhausted?()
                }
            } catch {
                failed.append(entry.appName)
            }
        }

        // Remove successfully uninstalled entries from the list.
        entries.removeAll { entry in
            succeeded.contains(entry.appName)
        }

        // 已卸载条目不再持有面板选中态（详情面板回落到空态）。
        if let selectedEntryID, !entries.contains(where: { $0.id == selectedEntryID }) {
            self.selectedEntryID = nil
        }

        return (succeeded, failed)
    }

    /// Recursive size used for the history rows (the scanner already
    /// computed it, but per-URL sizes are needed here).
    private static func sizeOf(_ url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? url.resourceValues(forKeys: [.fileSizeKey])).flatMap { values in
                values.fileSize.map(Int64.init)
            } ?? 0
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }
}
