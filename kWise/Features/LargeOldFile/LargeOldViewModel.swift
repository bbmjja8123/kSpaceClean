import Foundation
import SwiftUI

/// Sort field options exposed in the LargeOldView.
public enum LargeOldSortField: String, CaseIterable, Identifiable, Sendable {
    case size = "Size"
    case date = "Date"
    case name = "Name"
    case path = "Path"

    public var id: String { rawValue }
}

/// Main-actor view model that drives ``LargeOldView``.
@MainActor
public final class LargeOldViewModel: ObservableObject {
    // MARK: Published

    @Published public var entries: [LargeOldFileEntry] = []
    @Published public var isScanning = false
    @Published public var config = LargeOldScanConfig()
    @Published public var sortBy: LargeOldSortField = .size
    @Published public var sortAscending = false
    /// 文件列表 vs 文件夹聚合 (v2.3 Phase 5).
    @Published public var displayMode: DisplayMode = .files
    /// 文件类型筛选 (v2.4)：nil = 全部。
    @Published public var typeFilter: FileKindFilter?

    public enum FileKindFilter: String, CaseIterable, Identifiable {
        case video, audio, image, document, archive, diskImage
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .video: return "视频"
            case .audio: return "音频"
            case .image: return "图片"
            case .document: return "文档"
            case .archive: return "压缩包"
            case .diskImage: return "镜像"
            }
        }
        var extensions: Set<String> {
            switch self {
            case .video: return ["mp4", "mov", "mkv", "avi", "webm", "m4v", "wmv", "flv"]
            case .audio: return ["mp3", "wav", "aac", "flac", "m4a", "ogg", "aiff"]
            case .image: return ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp", "raw", "dng"]
            case .document: return ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "key", "numbers"]
            case .archive: return ["zip", "tar", "gz", "bz2", "7z", "rar", "zst"]
            case .diskImage: return ["dmg", "iso", "pkg"]
            }
        }
    }

    /// 类型过滤后的条目（files 模式渲染用）。
    public var filteredEntries: [LargeOldFileEntry] {
        guard let typeFilter else { return entries }
        return entries.filter { typeFilter.extensions.contains($0.url.pathExtension.lowercased()) }
    }

    public enum DisplayMode: String, CaseIterable {
        case files = "文件列表"
        case folders = "文件夹聚合"
    }

    /// One aggregated folder — computed from the current entries, no extra
    /// engine calls.
    public struct FolderAggregate: Identifiable {
        public let id: URL
        public let url: URL
        public let totalSize: Int64
        public let fileCount: Int
        public let oldestDate: Date?
        /// Share of the grand total, for the usage bar.
        public var fraction: Double { total > 0 ? Double(totalSize) / Double(total) : 0 }
        var total: Int64

        public init(id: URL, url: URL, totalSize: Int64, fileCount: Int,
                    oldestDate: Date?, total: Int64) {
            self.id = id
            self.url = url
            self.totalSize = totalSize
            self.fileCount = fileCount
            self.oldestDate = oldestDate
            self.total = total
        }
    }

    /// Folders aggregated from current entries (immediate parent grouping).
    public var folderAggregates: [FolderAggregate] {
        let byFolder = Dictionary(grouping: entries) { $0.url.deletingLastPathComponent() }
        let total = entries.reduce(Int64(0)) { $0 + $1.size }
        let aggs = byFolder.map { url, items in
            FolderAggregate(
                id: url, url: url,
                totalSize: items.reduce(0) { $0 + $1.size },
                fileCount: items.count,
                oldestDate: items.map(\.modificationDate).min(),
                total: total
            )
        }
        return aggs.sorted { $0.totalSize > $1.totalSize }
    }

    // MARK: Private

    private let scanner = LargeOldScanner()
    /// Structured-API engine (v2.0 Phase 2): cleanup lands in the 30-day
    /// history and consumes free-tier quota, exactly like the main surface.
    private(set) var engine: CleanupEngine
    public var onQuotaExhausted: (() -> Void)?
    /// Files skipped because a running process holds them open.
    @Published public var skippedInUseMessage: String?
    private var scanTask: Task<Void, Never>?

    public init(engine: CleanupEngine? = nil) {
        self.engine = engine ?? CleanupEngine.standard()
    }

    /// Re-point at the shared graph engine (v2.0 Phase 1 DI unification).
    public func useEngine(_ engine: CleanupEngine) {
        self.engine = engine
    }

    // MARK: Scanning

    public func startScan() {
        scanTask?.cancel()
        entries = []
        isScanning = true

        let cfg = config
        scanTask = Task { [weak self, scanner] in
            guard let self else { return }
            let stream = scanner.scan(config: cfg)

            for await entry in stream {
                if Task.isCancelled { break }
                await MainActor.run { [weak self] in
                    self?.entries.append(entry)
                }
            }

            if !Task.isCancelled {
                await MainActor.run { [weak self] in
                    self?.isScanning = false
                    self?.sort()
                }
            }
        }
    }

    public func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    // MARK: Computed

    public var totalSize: Int64 {
        entries.reduce(0) { $0 + $1.size }
    }

    public var selectedEntries: [LargeOldFileEntry] {
        entries.filter(\.isSelected)
    }

    public var selectedSize: Int64 {
        selectedEntries.reduce(0) { $0 + $1.size }
    }

    // MARK: Selection

    public func toggleSelection(_ id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].isSelected.toggle()
    }

    public func selectAll() {
        for i in entries.indices { entries[i].isSelected = true }
    }

    public func deselectAll() {
        for i in entries.indices { entries[i].isSelected = false }
    }

    // MARK: Sorting

    public func toggleSort(_ field: LargeOldSortField) {
        if sortBy == field {
            sortAscending.toggle()
        } else {
            sortBy = field
            sortAscending = (field == .name || field == .path)
        }
        sort()
    }

    public func sort() {
        switch sortBy {
        case .size:
            entries.sort { sortAscending ? $0.size < $1.size : $0.size > $1.size }
        case .date:
            entries.sort { sortAscending ? $0.modificationDate < $1.modificationDate : $0.modificationDate > $1.modificationDate }
        case .name:
            entries.sort { sortAscending ? $0.fileName < $1.fileName : $0.fileName > $1.fileName }
        case .path:
            entries.sort { sortAscending ? $0.path < $1.path : $0.path > $1.path }
        }
    }

    // MARK: Cleanup

    /// Moves all currently-selected files to the Trash via the shared
    /// cleanup engine (history + quota, v2.0 Phase 2).
    @discardableResult
    public func cleanupSelected() async -> TrashResult {
        let selected = selectedEntries
        guard !selected.isEmpty else { return TrashResult(snapshots: [], failed: []) }

        // In-use guard (v2.3 Phase 5): files held open by a running process
        // are skipped and reported, never silently failed (C-5).
        let warningService = WarningDetectionService()
        let warnItems = await warningService.detectWarnItems(for: selected.map(\.path))
        let inUsePaths = Set(warnItems.flatMap(\.conflictingPaths))
        let skippedInUse = selected.filter { inUsePaths.contains($0.path) }
        let cleanable = selected.filter { !inUsePaths.contains($0.path) }
        if !skippedInUse.isEmpty {
            skippedInUseMessage = skippedInUse.map { $0.fileName }.prefix(3).joined(separator: "、")
        } else {
            skippedInUseMessage = nil
        }
        guard !cleanable.isEmpty else { return TrashResult(snapshots: [], failed: []) }

        let targets = cleanable.map { entry in
            CleanupTarget(url: entry.url, size: entry.size, risk: .optional)
        }
        var result = TrashResult(snapshots: [], failed: [])
        do {
            let outcome = try await engine.cleanup(targets: targets)
            result = TrashResult(
                snapshots: outcome.succeeded.map {
                    TrashSnapshot(originalPath: $0.path, trashPath: $0.path,
                                  fileSize: 0, modifiedAt: Date())
                },
                failed: outcome.failed.map {
                    ($0.url, TrashMover.MoveError.trashFailed($0.url,
                        NSError(domain: "CleanupEngine", code: 0)))
                }
            )
            if outcome.quotaExhausted {
                onQuotaExhausted?()
            }
        } catch {
            // Best-effort — the view surfaces failures via the result.
        }

        // Remove successfully-trashed entries.
        let trashedPaths = Set(result.snapshots.map(\.originalPath))
        entries.removeAll { trashedPaths.contains($0.path) }

        return result
    }
}