import Foundation
import SwiftUI
import DetectionCore
import PowerScope

// MARK: - DuplicateViewModel (v2.3 Phase 2)

/// Main actor-bound view model driving the duplicate tool on the
/// DetectionCore pipeline. Groups are `ToolboxGroup`s (engine identity +
/// evidence + explainable selection preserved).
@MainActor
final class DuplicateViewModel: ObservableObject {
    // MARK: Published state

    @Published var groups: [ToolboxGroup] = []
    @Published var isScanning = false
    /// Fractional engine progress in [0, 1].
    @Published var scanProgress: Double = 0
    /// Files scanned so far (engine-reported).
    @Published var filesScanned: Int = 0
    /// Last warning from the engine (e.g. unreadable path), shown honestly.
    @Published var lastWarning: String?

    /// Root paths to scan. Defaults to PowerScope-probed readable dirs —
    /// NEVER `NSHomeDirectory()`, which under the App Sandbox is the
    /// container home (the pre-v2.3 bug that scanned nothing useful).
    @Published var scanPaths: [URL] = DuplicateViewModel.defaultScanPaths()

    /// Which copy to keep. Re-applies SelectionPlanner across all groups.
    @Published var strategy: SelectionStrategy = .keepNewest {
        didSet { reapplyStrategy() }
    }
    /// Similar-photo grouping aggressiveness (from Settings).
    @Published var preset: SimilarityPreset
    /// 场景预设 (v2.6 W1)：照片库 / 文档 / 开发目录。
    @Published var scenario: Scenario = .general

    enum Scenario: String, CaseIterable, Identifiable {
        case general = "通用"
        case photos = "照片库"
        case documents = "文档"
        case developer = "开发目录"

        var id: String { rawValue }
        var minFileSize: Int64 {
            switch self {
            case .general: return 1_048_576
            case .photos: return 128 * 1024      // 照片阈值更低
            case .documents: return 256 * 1024
            case .developer: return 1_048_576
            }
        }
        var enablePerceptual: Bool {
            switch self {
            case .photos: return true
            case .general: return true
            case .documents: return false   // 文档重复按字节比较更准
            case .developer: return false   // 开发目录按构建产物思路，另行处理
            }
        }
        var exclusions: [String] {
            switch self {
            case .developer: return ["node_modules", ".git", "DerivedData"]
            default: return []
            }
        }
    }

    // MARK: Private state

    private let scanner = DuplicateScanner()
    private(set) var engine: CleanupEngine
    var onQuotaExhausted: (() -> Void)?
    /// 最近一次清理的引擎结果 (v2.6 W1 收尾)——完成横幅的数据源。
    @Published private(set) var lastCleanupOutcome: CleanupOutcome?
    private var scanTask: Task<Void, Never>?
    private var controller: ScanController?

    /// PowerScope-honest default roots: probed public dirs that we can
    /// actually read, plus the home-scope favorites when home is granted.
    static func defaultScanPaths(capability: ScopeCapability? = nil) -> [URL] {
        var urls: [URL] = []
        let cap = capability ?? AppScope.shared.capability
        let home = FileManager.default.homeDirectoryForCurrentUser
        let favorites = [
            home.appendingPathComponent("Downloads", isDirectory: true),
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Pictures", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true),
        ]
        for url in favorites where cap.canRead(url) {
            urls.append(url)
        }
        if urls.isEmpty {
            urls = cap.readablePublicDirs.map { URL(fileURLWithPath: $0, isDirectory: true) }
        }
        return urls
    }

    // MARK: Lifecycle

    init(engine: CleanupEngine? = nil) {
        self.engine = engine ?? CleanupEngine.standard()
        // 恢复上次扫描目录（仍是 PowerScope-honest——上次授权的目录本次
        // 未必可读，startScan 前由 scanner 直接探测）。
        if let saved = UserDefaults.standard.stringArray(forKey: "kwise.duplicate.scanPaths") {
            scanPaths = saved.map { URL(fileURLWithPath: $0, isDirectory: true) }
        }
        self.preset = UserPreferences.load().similarityPreset
    }

    func useEngine(_ engine: CleanupEngine) {
        self.engine = engine
    }

    deinit {
        scanTask?.cancel()
        controller?.cancel()
    }

    // MARK: Scanning

    /// Starts (or restarts) the DetectionCore duplicate scan.
    func startScan() {
        scanTask?.cancel()
        controller?.cancel()
        groups = []
        isScanning = true
        scanProgress = 0
        filesScanned = 0
        lastWarning = nil

        let paths = scanPaths
        let activePreset = scenario == .photos ? preset : .strict
        let scenarioConfig = scenario
        let strategy = strategy
        let controller = ScanController()
        self.controller = controller

        scanTask = Task { [weak self, scanner] in
            let stream = scanner.scan(
                paths: paths, preset: activePreset, strategy: strategy,
                minFileSize: scenarioConfig.minFileSize,
                exclusions: scenarioConfig.exclusions,
                enablePerceptual: scenarioConfig.enablePerceptual
            )
            for await event in stream {
                guard let self else { return }
                switch event {
                case .progress(let progress):
                    self.scanProgress = progress.progress
                    self.filesScanned = progress.filesScanned
                case .group(let engineGroup):
                    let mapped = ToolboxGroup.map(engineGroup, strategy: strategy, scanRoots: paths)
                    self.groups.append(mapped)
                case .warning(let warning):
                    self.lastWarning = warning.message
                case .failed(let message):
                    self.lastWarning = message
                case .largeFiles, .completed:
                    break
                }
            }
            await MainActor.run { [weak self] in
                self?.isScanning = false
                self?.scanProgress = 1.0
            }
        }
    }

    /// Cancels the in-flight scan via the engine's ScanController; results
    /// found so far stay on screen.
    func cancelScan() {
        controller?.cancel()
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    // MARK: Computed properties

    /// Honest reclaimable space: Σ per-group honestlyReclaimable
    /// (clone sets report ~0 instead of the lying size × (n−1)).
    var totalWasted: Int64 {
        groups.reduce(0) { $0 + $1.honestlyReclaimable }
    }

    var selectedCount: Int {
        groups.reduce(0) { $0 + $1.files.filter(\.isSelected).count }
    }

    var selectedSize: Int64 {
        groups.reduce(0) { $0 + $1.files.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    }

    // MARK: Selection

    func toggleFile(_ id: UUID) {
        for gi in groups.indices {
            for fi in groups[gi].files.indices where groups[gi].files[fi].id == id {
                groups[gi].files[fi].isSelected.toggle()
                return
            }
        }
    }

    func toggleGroup(_ id: UUID) {
        guard let gi = groups.firstIndex(where: { $0.id == id }) else { return }
        let allSelected = groups[gi].files.allSatisfy(\.isSelected)
        for fi in groups[gi].files.indices {
            groups[gi].files[fi].isSelected = !allSelected
        }
    }

    /// Deselects every file in every group.
    func deselectAll() {
        for gi in groups.indices {
            for fi in groups[gi].files.indices {
                groups[gi].files[fi].isSelected = false
            }
        }
    }

    func toggleExpanded(_ id: UUID) {
        guard let gi = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[gi].isExpanded.toggle()
    }

    /// Re-applies the current selection strategy to every group: the keep
    /// copy is unchecked and gets its explanation badge; removals pre-check.
    func reapplyStrategy() {
        let roots = scanPaths
        for gi in groups.indices {
            groups[gi].reapplying(strategy: strategy, scanRoots: roots)
        }
    }

    // MARK: Cleanup

    /// Moves all currently-selected files to the Trash via the shared
    /// cleanup engine (30-day restorable history + free-tier quota).
    func cleanupSelected() async throws {
        let selected = groups.flatMap(\.files).filter(\.isSelected)
        guard !selected.isEmpty else { return }

        let targets = selected.map { file in
            CleanupTarget(url: file.url, size: file.size, risk: .caution)
        }
        let outcome = try await engine.cleanup(targets: targets)

        let trashedPaths = Set(outcome.succeeded.map(\.path))
        for gi in groups.indices.reversed() {
            groups[gi].files.removeAll { trashedPaths.contains($0.url.path) }
        }
        groups.removeAll { $0.files.isEmpty }

        if outcome.quotaExhausted {
            onQuotaExhausted?()
        }
        if let firstFailure = outcome.failed.first {
            throw TrashMover.MoveError.trashFailed(firstFailure.url,
                NSError(domain: "CleanupEngine", code: 0))
        }
    }
}

// MARK: - TrashMover.MoveError conformance

extension TrashMover.MoveError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .snapshotFailed(let url):
            return "Failed to record trash snapshot for: \(url.lastPathComponent)"
        case .trashFailed(let url, let underlying):
            return "Failed to move \"\(url.lastPathComponent)\" to Trash: \(underlying.localizedDescription)"
        }
    }
}
