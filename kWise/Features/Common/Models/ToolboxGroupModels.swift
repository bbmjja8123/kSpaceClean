// kWise/Features/Common/Models/ToolboxGroupModels.swift
//
// 引擎→工具箱映射层 (v2.3 Phase 1)。
//
// DetectionCore 的 `DuplicateGroup` 携带 category / similarity / evidence /
// 稳定 id，但 kWise 本地 UI 模型此前把它全部丢弃。`ToolboxGroup` 保留这些
// 字段，并把 `SelectionPlanner` 的每文件可解释原因（SelectionReason）贴到
// 行上。kWise 本地旧 `DuplicateGroup` 结构体在 Phase 2 移除后，本类型是
// 重复文件/照片工具唯一的 UI 数据源。
import Foundation
import DetectionCore

// MARK: - UI-facing group model

/// Why a file was kept or marked for removal — straight from SelectionPlanner.
struct ToolboxFile: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let size: Int64
    let modificationDate: Date
    let isAPFSClone: Bool
    var isSelected: Bool
    /// `SelectionReason.explanation` for the kept copy, or nil.
    var reason: String?
}

/// One duplicate/similar group rendered by the toolbox surfaces.
struct ToolboxGroup: Identifiable, Sendable {
    /// Engine group id — preserved so selection state survives re-mapping.
    let id: UUID
    let category: DuplicateCategory
    let similarity: Double?
    /// Chinese badge copy derived from `categoryEvidence`.
    let evidenceSummary: String
    var files: [ToolboxFile]
    var isExpanded: Bool
    /// Honest reclaimable math: APFS clone sets count `physicalSize` deltas
    /// (a clonefile copy reclaims almost nothing); byte-identical sets
    /// reclaim `fileSize × (count − 1)`.
    var honestlyReclaimable: Int64

    /// Maps an engine group and applies `strategy` via SelectionPlanner.
    /// The kept file is left unchecked; removals are pre-checked.
    static func map(_ engine: DetectionCore.DuplicateGroup,
                    strategy: SelectionStrategy,
                    scanRoots: [URL]) -> ToolboxGroup {
        var group = ToolboxGroup(
            id: engine.id,
            category: engine.category,
            similarity: engine.similarity,
            evidenceSummary: badge(for: engine.categoryEvidence),
            files: engine.files.map { item in
                ToolboxFile(
                    id: item.id,
                    url: item.url,
                    size: item.size,
                    modificationDate: item.modificationDate,
                    isAPFSClone: item.isAPFSClone,
                    isSelected: false,
                    reason: nil
                )
            },
            isExpanded: true,
            honestlyReclaimable: honestReclaimable(for: engine)
        )
        group.reapplying(strategy: strategy, scanRoots: scanRoots)
        return group
    }

    /// Re-runs SelectionPlanner with a new strategy: the keep copy gets its
    /// reason badge, removals become pre-checked.
    mutating func reapplying(strategy: SelectionStrategy, scanRoots: [URL]) {
        let engine = DetectionCore.DuplicateGroup(
            id: id,
            category: category,
            totalSize: files.reduce(0) { $0 + $1.size },
            fileCount: files.count,
            files: files.map { item in
                DetectionCore.FileItem(
                    id: item.id,
                    url: item.url,
                    size: item.size,
                    modificationDate: item.modificationDate,
                    creationDate: nil,
                    hash: nil,
                    fingerprint: nil,
                    inode: nil,
                    isAPFSClone: item.isAPFSClone,
                    physicalSize: nil
                )
            },
            categoryEvidence: .byteIdentical(sha256: "", byteVerified: false),
            similarity: similarity,
            scanTimestamp: Date()
        )
        let plan = SelectionPlanner.plan(for: engine, strategy: strategy, scanRoots: scanRoots)
        let keepID = plan.keep?.id
        let removeIDs = Set(plan.remove.map(\.id))

        for index in files.indices {
            files[index].isSelected = removeIDs.contains(files[index].id)
            if let keepID, files[index].id == keepID {
                files[index].reason = plan.reasons[keepID]?.explanation
            } else {
                files[index].reason = nil
            }
        }
    }
}

// MARK: - Honest reclaimable math

/// APFS clonefile copies share physical extents — trashing all but one
/// reclaims almost nothing. Byte-identical sets reclaim size × (n−1).
func honestReclaimable(for engine: DetectionCore.DuplicateGroup) -> Int64 {
    let uniquePhysical = Set(engine.files.compactMap(\.physicalSize))
    if engine.files.allSatisfy(\.isAPFSClone), uniquePhysical.count <= 1 {
        return 0
    }
    guard let size = engine.files.first?.size else { return 0 }
    return size * Int64(max(0, engine.files.count - 1))
}

// MARK: - Evidence badges (zh)

/// zh 徽标文案 — evidence → one line the UI can show on the group header.
func badge(for evidence: DetectionCore.CategoryEvidence) -> String {
    switch evidence {
    case .byteIdentical(_, let verified):
        return verified ? "字节级相同（已逐字节验证）" : "字节级相同"
    case .apfsClone:
        return "APFS 克隆副本"
    case .directoryDuplicate(_, let fileCount):
        return "目录级重复（\(fileCount) 个文件）"
    case .perceptualSimilarity(let distance, _):
        return String(format: "视觉相似 %.0f%%", (1 - distance) * 100)
    case .rawJPEGPair(_, _, let exifMatch):
        return exifMatch ? "RAW + JPEG 配对（EXIF 匹配）" : "RAW + JPEG 配对"
    case .buildArtifact:
        return "构建产物"
    case .largeFile:
        return "大文件"
    case .nameHeuristic(let stem, let count):
        return "同名变体「\(stem)」× \(count)"
    case .similarVideo(let ratio, _):
        return String(format: "相似视频（帧匹配 %.0f%%）", ratio * 100)
    }
}

// MARK: - Null repository (ScanOrchestrator DI)

/// No-persistence `DuplicateRepositoryProtocol` — kWise's toolbox surfaces
/// keep results in memory only, so ScanOrchestrator's required repository
/// parameter gets this instead of a Core Data store.
final class NullDuplicateRepository: DuplicateRepositoryProtocol, @unchecked Sendable {
    func saveScanRecord(_ record: DetectionCore.ScanRecord) async throws {}
    func loadScanRecords() async throws -> [DetectionCore.ScanRecord] { [] }
    func loadScanRecord(id: UUID) async throws -> DetectionCore.ScanRecord? { nil }
    func deleteScanRecord(id: UUID) async throws {}
    func saveCleanupAction(_ action: DetectionCore.CleanupAction) async throws {}
    func loadCleanupHistory() async throws -> [DetectionCore.CleanupRecord] { [] }
}
