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
