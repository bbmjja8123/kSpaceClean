// kWise/Features/Attribution/AttributionService.swift
//
// 归因整合（spec §4.3）：文件层（引擎）+ 卷层（diskutil）+ 黑盒数学 → 一份报告。
// 红线：只描述，不执行；未匹配的大项进拒答清单，小项并入残差（不刷屏）。
import Foundation

public struct AttributionReport: Sendable {
    /// 已归因且可给出可回收性判定（不含 .uncertain）。
    public let items: [SpaceAttribution]
    /// 拒答清单：匹配到规则但「不敢判」的 + 未匹配的大项。
    public let refused: [SpaceAttribution]
    /// 未匹配且小于阈值的小项合计 —— 并入黑盒叙事，不逐条列。
    public let unattributedBytes: Int64
    public let blackBox: BlackBoxBreakdown
    /// nil = 卷层不可读（spec §7 降级：明示，禁止 [] 冒充）。
    public let snapshots: [APFSSnapshot]?
    public let generatedAt: Date
}

public struct AttributionService: Sendable {
    /// 未匹配项进入拒答清单的大小门槛 —— 小于它不值得打扰用户。
    public static let refusedSizeThreshold: Int64 = 100 * 1024 * 1024

    public let engine: AttributionRuleEngine
    public let volumeReader: VolumeLayerReader?
    public let rootURL: URL
    public let volumeUsedBytesProvider: @Sendable () -> Int64?

    public init(engine: AttributionRuleEngine,
                volumeReader: VolumeLayerReader? = VolumeLayerReader(),
                rootURL: URL = URL(fileURLWithPath: "/"),
                volumeUsedBytesProvider: @escaping @Sendable () -> Int64?
                    = { AttributionService.systemVolumeUsedBytes() }) {
        self.engine = engine
        self.volumeReader = volumeReader
        self.rootURL = rootURL
        self.volumeUsedBytesProvider = volumeUsedBytesProvider
    }

    /// 生产装配：语料来自 App 包。语料缺失 → 空语料（一切进拒答，诚实降级）。
    ///
    /// `home` 默认走 `UserPathResolver.realHomeDirectory()`（真实用户家目录），
    /// 绝不能用 `NSHomeDirectory()` —— 沙箱下它返回容器路径，而扫描结果携带的
    /// 是真实家目录路径，两者对不上则所有 `~/Library/...` 语料 glob 永不命中
    /// （final review C1：live() 语料整体失效的根因）。
    /// 参数化 `home` 仅为测试接缝；生产调用点保持无参 `live()`。
    public static func live(home: String = UserPathResolver.realHomeDirectory()) -> AttributionService {
        let corpus = Bundle.main.url(forResource: "attribution_rules", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? AttributionRuleCorpus.load(from: $0) }
            ?? AttributionRuleCorpus(schemaVersion: 1, rules: [])
        return AttributionService(engine: AttributionRuleEngine(
            corpus: corpus, homeDirectory: home))
    }

    public func attribute(categories: [ScanCategory]) async -> AttributionReport {
        var results: [ScanResult] = []
        for category in categories {
            Self.flatten(category, into: &results)
        }
        let visibleBytes = results.reduce(Int64(0)) { $0 + $1.fileSize }

        var items: [SpaceAttribution] = []
        var refused: [SpaceAttribution] = []
        var unattributedBytes: Int64 = 0
        for attribution in engine.attribute(results: results) {
            // final review M4（L1 路由陷阱）：下面的 `default:` 分支假设引擎只产出
            // `.certain` / `.refused`。L1/L2（阈值归因，产出 `.probable`）接线后，
            // 这里的隐式假设必须由该实现显式接管 —— 在此 fail loud，禁止 L1 实现者
            // 无意间把 `.probable` 静默吞进阈值路由（spec §4.5）。
            precondition(attribution.confidence != .probable,
                         "L1/L2 routing not wired yet — see spec §4.5")
            switch (attribution.confidence, attribution.reclaim) {
            case (.certain, .uncertain):
                refused.append(attribution)
            case (.certain, _):
                items.append(attribution)
            default:
                if attribution.bytes >= Self.refusedSizeThreshold {
                    refused.append(attribution)
                } else {
                    unattributedBytes += attribution.bytes
                }
            }
        }

        let snapshots: [APFSSnapshot]?
        if let volumeReader {
            snapshots = try? await volumeReader.listSnapshots()
        } else {
            snapshots = nil
        }
        let blackBox = BlackBoxMath.reconcile(
            usedBytes: volumeUsedBytesProvider(),
            visibleBytes: visibleBytes,
            snapshotCount: snapshots?.count ?? 0)

        return AttributionReport(items: items, refused: refused,
                                 unattributedBytes: unattributedBytes,
                                 blackBox: blackBox, snapshots: snapshots,
                                 generatedAt: Date())
    }

    /// 纯内存后序遍历 —— 不触发任何文件系统调用（spec §4.3 只读接缝）。
    ///
    /// 注：`ScanSubCategory.showAction == true` 时 `children` 只含 `actions`，
    /// `directResults` 不在其中 —— 这里显式补走，保证两路结果都被计入
    /// （与 testFlattenWalksWholeTree 的生产形状契约一致）。
    static func flatten(_ node: any ScanTreeNode, into results: inout [ScanResult]) {
        if let result = node as? ScanResult {
            results.append(result)
        }
        for child in node.children {
            flatten(child, into: &results)
        }
        if let sub = node as? ScanSubCategory, sub.showAction {
            for child in sub.directResults {
                flatten(child, into: &results)
            }
        }
    }

    /// 卷用量 = 总容量 − 「重要用途可用」（含 purgeable 口径，Apple 文档语义）。
    /// 参数化 `rootURL`（默认系统卷根），以便静态默认装配复用同一实现。
    /// （public：作为 `init` 默认实参出现，必须对模块外调用点可见。）
    public static func systemVolumeUsedBytes(rootURL: URL = URL(fileURLWithPath: "/")) -> Int64? {
        let values = try? rootURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ])
        guard let total = values?.volumeTotalCapacity,
              let available = values?.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return Int64(total) - available
    }
}
