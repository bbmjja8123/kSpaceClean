// kWise/Features/Anatomy/CanvasGroup.swift
//
// 画布数据层（P2 T2，spec §2/§3）：归因 + 三个检测器 → 动态分组的
// `CanvasGroup` 模型与纯函数组装器 `CanvasGroupAssembler`。
//
// 组规则（spec §2 动态分组，全部在本文件落地）：
// - 空组不出现 —— 条目为空或字节为 0 的组由组装器返回 nil；
// - 「我不敢判的」（refused）不占 CanvasGroup —— 派生为 `UncertainCard`
//   虚线卡数据，由画布单独渲染；
// - 条目间按路径 `uniquingKeysWith` 去重，组间按 totalBytes 降序。
import Foundation
import DetectionCore

// MARK: - Model

/// 画布组的身份：归因 cause 组（找到才出现）或三个检测器组。
public enum GroupKind: Equatable, Hashable, Sendable {
    case cause(AttributionCause)
    case duplicates
    case similarPhotos
    case largeFiles
}

/// 五色徽章语义（plan Global Constraints）：
/// 绿 ✓ 可回收 / 蓝迁出引导 / 橙 ⚠ 注意 / 红数据·不属垃圾 / 灰不动·不敢判。
public enum BadgeKind: Equatable, Sendable {
    case recyclable
    case migrate
    case attention
    case dataNotJunk
    case leaveAlone
}

/// 组内一条可解释条目。`target` 供统一预演（T5/T6 复用 P1 预演链）。
public struct CanvasEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let bytes: Int64
    public let badge: BadgeKind
    public let detail: String?
    public let target: CleanupTarget?

    public init(id: UUID = UUID(),
                title: String,
                bytes: Int64,
                badge: BadgeKind,
                detail: String? = nil,
                target: CleanupTarget? = nil) {
        self.id = id
        self.title = title
        self.bytes = bytes
        self.badge = badge
        self.detail = detail
        self.target = target
    }

    /// Reclaimability → 五色徽章（绑定映射）：
    /// recycles→.recyclable / resurrects→.attention / permanent→.dataNotJunk /
    /// uncertain→.leaveAlone。`.migrate` 只由检测器组（大文件迁出）赋予。
    public static func badge(forReclaim reclaim: Reclaimability) -> BadgeKind {
        switch reclaim {
        case .recycles: return .recyclable
        case .resurrects: return .attention
        case .permanent: return .dataNotJunk
        case .uncertain: return .leaveAlone
        }
    }
}

/// 组头动作动词（CanvasGroupCard 据此决定按钮）：
/// `.rehearse→就地清理` / `.guidance→正确解法`（弹命令面板）/
/// `.migrate→迁出引导` / `.none→无按钮`。
public enum GroupAction: Equatable, Sendable {
    case rehearse
    case guidance(text: String)
    case migrate
    case none
}

/// 画布上的一个动态组。
public struct CanvasGroup: Identifiable, Equatable, Sendable {
    public let id: GroupKind
    public let icon: String
    public let title: String
    public let subtitle: String
    public let totalBytes: Int64
    public let entries: [CanvasEntry]
    public let action: GroupAction
}

/// 「我不敢判的」虚线卡数据 —— 从 refused 派生，不占 CanvasGroup。
public struct UncertainCard: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let totalBytes: Int64
    public let items: [SpaceAttribution]
}

// MARK: - Assembler

/// 纯函数组装器：scanner 产出的中间类型 → CanvasGroup。
/// 不启扫描即可测（CanvasGroupTests 不触碰文件系统）。
public enum CanvasGroupAssembler {

    /// 条目数量上限 —— 画布组卡只展示头部条目，全量进下钻页。
    static let maxEntriesPerGroup = 20

    // MARK: 核心组装

    /// 条目 → 组。条目为空或字节为 0 → nil（空组不出现）。
    /// `title` / `subtitle` / `action` 缺省时由 kind 派生；`totalBytes`
    /// 缺省时取条目合计（检测组显式传入诚实回收字节）。
    public static func assemble(kind: GroupKind,
                                icon: String,
                                title: String? = nil,
                                subtitle: String? = nil,
                                action: GroupAction? = nil,
                                entries: [CanvasEntry],
                                totalBytes: Int64? = nil) -> CanvasGroup? {
        let deduped = deduplicate(entries: entries)
        let bytes = totalBytes ?? deduped.reduce(Int64(0)) { $0 + $1.bytes }
        guard !deduped.isEmpty, bytes > 0 else { return nil }
        return CanvasGroup(
            id: kind,
            icon: icon,
            title: title ?? defaultTitle(kind),
            subtitle: subtitle ?? defaultSubtitle(kind),
            totalBytes: bytes,
            entries: Array(deduped.prefix(maxEntriesPerGroup)),
            action: action ?? defaultAction(kind))
    }

    // MARK: 归因 cause 组

    /// 归因 items 按 cause 分组：组内条目 bytes 降序、组间 totalBytes 降序。
    /// `reclaim == .uncertain` 的项不会出现在 `report.items`（AttributionService
    /// 路由保证），这里再挡一层 —— 「我不敢判的」绝不进 CanvasGroup。
    public static func assembleCauseGroups(from items: [SpaceAttribution]) -> [CanvasGroup] {
        let eligible = items.filter { $0.reclaim != .uncertain }
        guard !eligible.isEmpty else { return [] }
        return Dictionary(grouping: eligible, by: \.cause)
            .map { cause, group in
                let entries = group
                    .compactMap { causeEntry(from: $0) }
                    .sorted { $0.bytes > $1.bytes }
                // subtitle = 组内最大项的诚实定性（reclaim 文案复用 attr.reclaim.*）。
                let dominant = group.max { $0.bytes < $1.bytes }
                let subtitle = dominant.map { AttributionCopy.reclaimLabel($0.reclaim) } ?? ""
                let action: GroupAction
                if let resurrect = group.first(where: {
                    if case .resurrects = $0.reclaim { return true }
                    return false
                }), case .resurrects(let via) = resurrect.reclaim {
                    action = .guidance(text: via)
                } else {
                    action = .rehearse
                }
                return assemble(kind: .cause(cause),
                                icon: icon(for: .cause(cause)),
                                subtitle: subtitle,
                                action: action,
                                entries: entries)
            }
            .compactMap { $0 }
            .sorted { $0.totalBytes > $1.totalBytes }
    }

    private static func causeEntry(from item: SpaceAttribution) -> CanvasEntry? {
        guard let path = item.paths.first else { return nil }
        return CanvasEntry(
            id: item.id,
            title: URL(fileURLWithPath: path).lastPathComponent,
            bytes: item.bytes,
            badge: CanvasEntry.badge(forReclaim: item.reclaim),
            detail: path,
            target: CleanupTarget(
                url: URL(fileURLWithPath: path),
                size: item.bytes,
                risk: riskLevel(for: CanvasEntry.badge(forReclaim: item.reclaim)),
                bundleID: ownerBundleID(item.owner),
                categoryID: item.ruleID))
    }

    // MARK: 检测器组

    /// 重复文件组 —— 复用 P0 的 `ToolboxGroup.map`（SelectionPlanner reason +
    /// honestReclaimable）。totalBytes = Σ honestReclaimable（APFS 克隆集诚实为 0
    /// → 整组不出现），条目 = 被选中移除的多余副本。
    /// （internal：参数 `ToolboxGroup` 是 app 内部 UI 模型。）
    static func assembleDuplicates(from groups: [ToolboxGroup]) -> CanvasGroup? {
        detectorGroup(kind: .duplicates, groups: groups, categoryID: "duplicates")
    }

    /// 相似照片组 —— PhotoSimilarityScanner 产出引擎 DuplicateGroup，同样经
    /// `ToolboxGroup.map` 走 SelectionPlanner（理由可解释，与重复组同源）。
    static func assemblePhotos(from groups: [ToolboxGroup]) -> CanvasGroup? {
        detectorGroup(kind: .similarPhotos, groups: groups, categoryID: "similarPhotos")
    }

    private static func detectorGroup(kind: GroupKind,
                                      groups: [ToolboxGroup],
                                      categoryID: String) -> CanvasGroup? {
        let entries = groups.flatMap { group in
            group.files.filter(\.isSelected).map { file in
                CanvasEntry(
                    id: file.id,
                    title: file.url.lastPathComponent,
                    bytes: file.size,
                    badge: .recyclable,
                    detail: file.url.deletingLastPathComponent().path,
                    target: CleanupTarget(
                        id: file.id,
                        url: file.url,
                        size: file.size,
                        risk: .recommended,
                        categoryID: categoryID))
            }
        }
        let honestBytes = groups.reduce(Int64(0)) { $0 + $1.honestlyReclaimable }
        return assemble(kind: kind,
                        icon: icon(for: kind),
                        entries: entries,
                        totalBytes: honestBytes)
    }

    /// 大/旧文件组 —— 蓝徽迁出语义：大文件的首要正确动作是迁出而非删除。
    public static func assembleLargeFiles(from entries: [LargeOldFileEntry]) -> CanvasGroup? {
        let canvasEntries = entries.map { entry in
            CanvasEntry(
                id: entry.id,
                title: entry.fileName,
                bytes: entry.size,
                badge: .migrate,
                detail: entry.url.deletingLastPathComponent().path,
                target: CleanupTarget(
                    id: entry.id,
                    url: entry.url,
                    size: entry.size,
                    risk: .optional,
                    categoryID: "largeFiles"))
        }
        return assemble(kind: .largeFiles, icon: icon(for: .largeFiles), entries: canvasEntries)
    }

    // MARK: 拒答虚线卡

    /// refused → 虚线卡数据；清单为空 → nil（与空组不出现同一原则）。
    public static func uncertainCard(from refused: [SpaceAttribution]) -> UncertainCard? {
        guard !refused.isEmpty else { return nil }
        let sorted = refused.sorted { $0.bytes > $1.bytes }
        return UncertainCard(id: UUID(),
                             totalBytes: sorted.reduce(Int64(0)) { $0 + $1.bytes },
                             items: sorted)
    }

    // MARK: 派生默认值

    private static func defaultTitle(_ kind: GroupKind) -> String {
        switch kind {
        case .cause(let cause): return AttributionCopy.causeLabel(cause)
        case .duplicates: return String(localized: String.LocalizationValue("canvas.group.duplicates.title"))
        case .similarPhotos: return String(localized: String.LocalizationValue("canvas.group.similarPhotos.title"))
        case .largeFiles: return String(localized: String.LocalizationValue("canvas.group.largeFiles.title"))
        }
    }

    private static func defaultSubtitle(_ kind: GroupKind) -> String {
        switch kind {
        case .duplicates: return String(localized: String.LocalizationValue("canvas.group.duplicates.subtitle"))
        case .similarPhotos: return String(localized: String.LocalizationValue("canvas.group.similarPhotos.subtitle"))
        case .largeFiles: return String(localized: String.LocalizationValue("canvas.group.largeFiles.subtitle"))
        case .cause: return ""
        }
    }

    private static func defaultAction(_ kind: GroupKind) -> GroupAction {
        switch kind {
        case .duplicates, .similarPhotos: return .rehearse
        case .largeFiles: return .migrate
        case .cause: return .rehearse
        }
    }

    /// SF Symbol —— cause 五色之外的视觉锚点（画布组卡左上角）。
    public static func icon(for kind: GroupKind) -> String {
        switch kind {
        case .cause(let cause):
            switch cause {
            case .cache: return "trash"
            case .snapshot: return "clock.arrow.circlepath"
            case .developerCache: return "hammer"
            case .aiModel: return "brain"
            case .chatFiles: return "bubble.left.and.bubble.right"
            case .renderCache: return "film"
            case .download: return "arrow.down.circle"
            case .archive: return "doc.zipper"
            case .backup: return "externaldrive.badge.timemachine"
            case .log: return "doc.text"
            case .mailAttachment: return "envelope"
            case .iOSBackup: return "iphone"
            case .containerData: return "shippingbox"
            case .unknown: return "questionmark.circle"
            }
        case .duplicates: return "doc.on.doc"
        case .similarPhotos: return "photo.on.rectangle.angled"
        case .largeFiles: return "externaldrive"
        }
    }

    // MARK: Helpers

    /// 同一路径只保留字节更大的一条（uniquingKeysWith）。无 target 的条目
    /// 以自身 id 兜底键，永不被合并。
    private static func deduplicate(entries: [CanvasEntry]) -> [CanvasEntry] {
        let keyed = entries.map { entry in
            (entry.target?.url.path ?? entry.id.uuidString, entry)
        }
        let deduped = Dictionary(keyed, uniquingKeysWith: { a, b in
            a.bytes >= b.bytes ? a : b
        })
        return deduped.values.sorted { $0.bytes > $1.bytes }
    }

    /// 徽章 → 风险级（CleanupTarget 契约；C4 红线：leaveAlone 标 dangerous，
    /// 永不自动进清理集）。
    private static func riskLevel(for badge: BadgeKind) -> RiskLevel {
        switch badge {
        case .recyclable: return .recommended
        case .migrate: return .optional
        case .attention: return .caution
        case .dataNotJunk: return .optional
        case .leaveAlone: return .dangerous
        }
    }

    private static func ownerBundleID(_ owner: AttributionOwner) -> String? {
        if case .app(let bundleID, _) = owner { return bundleID }
        return nil
    }
}
