// kWise/Features/Anatomy/CanvasScanCoordinator.swift
//
// 画布扇出扫描（P2 T2，spec §5 扫描即动作；Task 8 扩第五缝）：
//   归因（已有 AsyncStream）→ 重复 → 照片 → 大文件 → 家务三组。
// 每段完成即把组推上画布（增量产出，画布不清空）；检测器为 nil
// （未授权 / 已关闭）时对应段跳过 —— 不出空组。
//
// 检测器与归因服务都包 protocol seam（DuplicateScanning /
// PhotoScanning / LargeFileScanning / HousekeepingScanning /
// AttributionScanning），测试注入 mock（CanvasScanCoordinatorTests 零
// 文件系统触达），生产包真实现。HousekeepingScanning 定义在
// HousekeepingDetector.swift（seam 与实现同文件，不在此重复声明）。
import Foundation
import DetectionCore
import Combine

// MARK: - Scanner seams

/// 归因服务 seam（AttributionService 为 struct，直接贴合其唯一入口）。
public protocol AttributionScanning: Sendable {
    func attribute(categories: [ScanCategory]) async -> AttributionReport
}

extension AttributionService: AttributionScanning {}

/// 重复检测 seam —— 贴合 `DuplicateScanner.scan` 真实签名
/// （DetectionCore ScanOrchestrator 的 ScanEvent 流）。
public protocol DuplicateScanning: Sendable {
    func scan(paths: [URL],
              preset: SimilarityPreset,
              strategy: SelectionStrategy,
              minFileSize: Int64,
              exclusions: [String],
              enablePerceptual: Bool) -> AsyncStream<DetectionCore.ScanEvent>
}

extension DuplicateScanner: DuplicateScanning {}

/// 相似照片检测 seam —— 贴合 `PhotoSimilarityScanner.scan` 真实签名
/// （PhotoSimilarityConfig + ScanController + progress 回调）。
public protocol PhotoScanning: Sendable {
    func scan(config: PhotoSimilarityConfig,
              controller: ScanController,
              progress: @escaping @Sendable (Double, String?) -> Void)
        async -> [DetectionCore.DuplicateGroup]
}

extension PhotoSimilarityScanner: PhotoScanning {}

/// 大/旧文件检测 seam —— 贴合 `LargeOldScanner.scan` 真实签名
/// （AsyncStream<LargeOldFileEntry>）。
public protocol LargeFileScanning: Sendable {
    func scan(config: LargeOldScanConfig) -> AsyncStream<LargeOldFileEntry>
}

extension LargeOldScanner: LargeFileScanning {}

// MARK: - Scope & Report

/// 一次画布扫描的输入范围：归因吃扫描树分类，检测器吃各自授权根目录。
public struct CanvasScanScope: Sendable {
    public var categories: [ScanCategory]
    public var duplicateRoots: [URL]
    public var photoDirectories: [URL]
    public var largeFileRoots: [URL]
    /// 家务三组的授权根（Task 8）：主目录书签根 / grantedRoot；nil =
    /// container-only —— 检测器返回空，协调器上 `skippedHousekeeping`
    /// 诊断（禁止静默丢弃，R2 先例）。默认 nil：不传 = 未授权语义。
    public var housekeepingHome: URL?
    public var selectionStrategy: SelectionStrategy
    public var preset: SimilarityPreset

    public init(categories: [ScanCategory],
                duplicateRoots: [URL],
                photoDirectories: [URL],
                largeFileRoots: [URL],
                housekeepingHome: URL? = nil,
                selectionStrategy: SelectionStrategy = .keepNewest,
                preset: SimilarityPreset = .normal) {
        self.categories = categories
        self.duplicateRoots = duplicateRoots
        self.photoDirectories = photoDirectories
        self.largeFileRoots = largeFileRoots
        self.housekeepingHome = housekeepingHome
        self.selectionStrategy = selectionStrategy
        self.preset = preset
    }
}

/// 画布扫描报告 —— `groups` 按扇出完成顺序排列（画布即完成顺序）。
public struct CanvasReport: Sendable {
    public let groups: [CanvasGroup]
    /// 黑盒残差（P0）：nil 仅在归因未运行时出现 —— 生产路径恒非 nil。
    public let uncovered: BlackBoxBreakdown?
    /// nil = 卷层不可读（P1 契约：明示降级，禁止 [] 冒充）。
    public let snapshots: [APFSSnapshot]?
    public let generatedAt: Date

    public init(groups: [CanvasGroup],
                uncovered: BlackBoxBreakdown?,
                snapshots: [APFSSnapshot]?,
                generatedAt: Date) {
        self.groups = groups
        self.uncovered = uncovered
        self.snapshots = snapshots
        self.generatedAt = generatedAt
    }
}

// MARK: - Coordinator

@MainActor
public final class CanvasScanCoordinator: ObservableObject {

    /// 增量产出的组（每组完成即追加，顺序 = 扇出完成顺序）。
    @Published public private(set) var groups: [CanvasGroup] = []
    /// 「我不敢判的」虚线卡数据（不占 CanvasGroup，画布单独渲染）。
    @Published public private(set) var uncertainCard: UncertainCard?
    @Published public private(set) var isRunning = false
    /// 扫描诊断（检测器 `.failed` / `.warning` / 重入提示）—— T3 据此显示
    /// 降级态文案。管线中途失败时对应组消失，但**绝不静默**（fix r1）。
    @Published public private(set) var scanDiagnostics: [String] = []

    /// P3 诚实性（MasScanScope.md 红线 2）：引擎扫描因 scope 不可读而跳过
    /// 的根必须可见地落在画布诊断区 —— 禁止静默丢弃（"没扫到"≠"干净"）。
    public func noteSkippedRegions(_ names: [String]) {
        guard !names.isEmpty else { return }
        scanDiagnostics.append(String(
            format: String(localized: String.LocalizationValue("canvas.diagnostic.skippedRegions")),
            names.joined(separator: "、")))
    }

    private let attributionService: any AttributionScanning
    private let duplicateScanner: (any DuplicateScanning)?
    private let photoScanner: (any PhotoScanning)?
    private let largeFileScanner: (any LargeFileScanning)?
    /// 家务三组检测器（Task 8 第五缝）。
    private let housekeepingScanner: (any HousekeepingScanning)?

    /// 重复检测下限沿用 v2.3 工具默认（1 MiB）—— 画布不重复暴露该旋钮。
    static let duplicateMinFileSize: Int64 = 1_048_576

    public init(attributionService: any AttributionScanning = AttributionService.live(),
                duplicateScanner: (any DuplicateScanning)? = DuplicateScanner(),
                photoScanner: (any PhotoScanning)? = PhotoSimilarityScanner(),
                largeFileScanner: (any LargeFileScanning)? = LargeOldScanner(),
                housekeepingScanner: (any HousekeepingScanning)? = HousekeepingDetector()) {
        self.attributionService = attributionService
        self.duplicateScanner = duplicateScanner
        self.photoScanner = photoScanner
        self.largeFileScanner = largeFileScanner
        self.housekeepingScanner = housekeepingScanner
    }

    /// 扇出顺序：归因 → 重复 → 照片 → 大文件 → 家务。
    /// 重入守卫（fix r1 ④）：扫描进行中再次调用 → 直接 return 当前增量
    /// 状态并记诊断，不打断进行中的扫描。
    public func runScan(scope: CanvasScanScope) async -> CanvasReport {
        if isRunning {
            scanDiagnostics.append(String(
                localized: String.LocalizationValue("canvas.diagnostic.scanInProgress")))
            return CanvasReport(groups: groups,
                                uncovered: nil, snapshots: nil, generatedAt: Date())
        }
        groups = []
        uncertainCard = nil
        scanDiagnostics = []
        isRunning = true
        defer { isRunning = false }

        // 1. 归因（组随流产出，cause 组间已按 totalBytes 降序）。
        let report = await attributionService.attribute(categories: scope.categories)
        uncertainCard = CanvasGroupAssembler.uncertainCard(from: report.refused)
        groups.append(contentsOf: CanvasGroupAssembler.assembleCauseGroups(from: report.items))

        // 2. 重复文件。`.failed` / `.warning` 进诊断通道（fix r1：禁止静默丢弃）。
        if let duplicateScanner {
            var engineGroups: [DetectionCore.DuplicateGroup] = []
            for await event in duplicateScanner.scan(
                paths: scope.duplicateRoots,
                preset: scope.preset,
                strategy: scope.selectionStrategy,
                minFileSize: Self.duplicateMinFileSize,
                exclusions: [],
                enablePerceptual: true) {
                switch event {
                case .group(let engineGroup):
                    engineGroups.append(engineGroup)
                case .failed(let message):
                    scanDiagnostics.append(message)
                case .warning(let warning):
                    scanDiagnostics.append(warning.message)
                case .progress, .largeFiles, .completed:
                    break
                }
            }
            let mapped = engineGroups.map {
                ToolboxGroup.map($0, strategy: scope.selectionStrategy,
                                 scanRoots: scope.duplicateRoots)
            }
            if let group = CanvasGroupAssembler.assembleDuplicates(from: mapped) {
                groups.append(group)
            }
        }

        // 3. 相似照片。
        if let photoScanner {
            let photoGroups = await photoScanner.scan(
                config: PhotoSimilarityConfig(directories: scope.photoDirectories,
                                              preset: scope.preset),
                controller: ScanController()) { _, _ in }
            let mapped = photoGroups.map {
                ToolboxGroup.map($0, strategy: scope.selectionStrategy,
                                 scanRoots: scope.photoDirectories)
            }
            if let group = CanvasGroupAssembler.assemblePhotos(from: mapped) {
                groups.append(group)
            }
        }

        // 4. 大/旧文件。
        if let largeFileScanner {
            var entries: [LargeOldFileEntry] = []
            for await entry in largeFileScanner.scan(
                config: LargeOldScanConfig(scanPaths: scope.largeFileRoots)) {
                entries.append(entry)
            }
            if let group = CanvasGroupAssembler.assembleLargeFiles(from: entries) {
                groups.append(group)
            }
        }

        // 5. 家务三组（Task 8）：iOS 设备备份 / 下载分诊 / 废纸篓大项。
        // container-only（housekeepingHome == nil）→ 检测器返回空，此时必须
        // 上画布诊断（MasScanScope.md 红线 2：禁止静默丢弃 —— "没扫到"≠"干净"）。
        if let housekeepingScanner {
            let findings = await housekeepingScanner.scan(homeURL: scope.housekeepingHome)
            if findings.isEmpty, scope.housekeepingHome == nil {
                scanDiagnostics.append(String(
                    localized: String.LocalizationValue("canvas.diagnostic.skippedHousekeeping")))
            }
            groups.append(contentsOf: CanvasGroupAssembler.assembleHousekeeping(from: findings))
        }

        // 报告按 totalBytes 降序（fix r1 ③）；增量填充顺序见 `groups`
        // published 属性 —— 画布在扫描期间仍按完成顺序逐组出现。
        return CanvasReport(groups: groups.sorted { $0.totalBytes > $1.totalBytes },
                            uncovered: report.blackBox,
                            snapshots: report.snapshots,
                            generatedAt: Date())
    }
}
