// kWise/Features/PhotoClean/PhotoSimilarityViewModel.swift
//
// 相似照片 Tab 的视图模型 (v2.3 Phase 3) — DetectionCore 感知哈希分组，
// 组内 keep≥1 级联勾选，清理走共享 CleanupEngine（30 天可恢复历史 + 配额）。
import Foundation
import SwiftUI
import DetectionCore
import PowerScope

@MainActor
final class PhotoSimilarityViewModel: ObservableObject {
    @Published private(set) var groups: [ToolboxGroup] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scanProgress: Double = 0
    @Published private(set) var currentFile: String?
    @Published private(set) var statusMessage: String?

    /// Candidate directories the current scope can read — empty in
    /// container-only mode, which drives the honest grant CTA.
    var candidateDirectories: [URL] {
        PhotoSimilarityScanner.candidateDirectories(capability: AppScope.shared.capability)
    }

    private(set) var engine: CleanupEngine
    var onQuotaExhausted: (() -> Void)?
    private let scanner = PhotoSimilarityScanner()
    private var controller: DetectionCore.ScanController?
    private var scanTask: Task<Void, Never>?

    init(engine: CleanupEngine? = nil) {
        self.engine = engine ?? CleanupEngine.standard()
    }

    func useEngine(_ engine: CleanupEngine) {
        self.engine = engine
    }

    var selectedFiles: [ToolboxFile] {
        groups.flatMap(\.files).filter(\.isSelected)
    }

    var selectedSize: Int64 {
        selectedFiles.reduce(0) { $0 + $1.size }
    }

    var totalReclaimable: Int64 {
        groups.reduce(0) { $0 + $1.honestlyReclaimable }
    }

    // MARK: - Scan

    func startScan() {
        guard !isScanning else { return }
        let dirs = candidateDirectories
        guard !dirs.isEmpty else {
            statusMessage = "当前授权范围无法读取照片目录"
            return
        }
        isScanning = true
        scanProgress = 0
        groups = []
        statusMessage = nil

        let config = PhotoSimilarityConfig(
            directories: dirs,
            preset: UserPreferences.load().similarityPreset
        )
        let controller = DetectionCore.ScanController()
        self.controller = controller

        scanTask = Task { [weak self, scanner] in
            let groups = await scanner.scan(config: config, controller: controller) { fraction, file in
                Task { @MainActor [weak self] in
                    self?.scanProgress = fraction
                    self?.currentFile = file
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.groups = groups.map {
                    ToolboxGroup.map($0, strategy: .keepNewest, scanRoots: config.directories)
                }
                self.isScanning = false
                self.scanProgress = 1.0
                if self.groups.isEmpty {
                    self.statusMessage = "未发现相似的 photos — 这些目录很干净。"
                }
            }
        }
    }

    func cancelScan() {
        controller?.cancel()
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    // MARK: - Selection

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

    /// 组内至少保留一张 — 全选被拒绝并给出诚实提示（C-5）。
    func selectAllInGroup(_ id: UUID) {
        guard let gi = groups.firstIndex(where: { $0.id == id }) else { return }
        statusMessage = "每组至少保留一张照片，不能全部删除。"
        for fi in groups[gi].files.indices.dropFirst() {
            groups[gi].files[fi].isSelected = true
        }
    }

    func deselectAll() {
        for gi in groups.indices {
            for fi in groups[gi].files.indices {
                groups[gi].files[fi].isSelected = false
            }
        }
    }

    // MARK: - Cleanup

    func cleanupSelected() async {
        let selected = selectedFiles
        guard !selected.isEmpty else { return }
        let targets = selected.map { file in
            CleanupTarget(url: file.url, size: file.size, risk: .caution)
        }
        do {
            let outcome = try await engine.cleanup(targets: targets)
            let trashed = Set(outcome.succeeded.map(\.path))
            for gi in groups.indices.reversed() {
                groups[gi].files.removeAll { trashed.contains($0.url.path) }
            }
            groups.removeAll { $0.files.isEmpty }
            if outcome.quotaExhausted {
                onQuotaExhausted?()
            }
        } catch {
            statusMessage = "清理失败：\(error.localizedDescription)"
        }
    }
}
