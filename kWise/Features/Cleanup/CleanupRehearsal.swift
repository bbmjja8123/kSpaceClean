// kWise/Features/Cleanup/CleanupRehearsal.swift
//
// 预演数据层（spec §5 Rehearsal）。红线：与执行 1:1 同序——预演撒谎 = 信任崩塌
// （P0 评审原话）。归因信息是「为什么可以回收」的展示层，缺席时诚实留空。
import Foundation

public struct RehearsalItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let target: CleanupTarget
    /// 该项的归因（可能为 nil——展示层必须诚实渲染「无归因信息」）。
    public let attribution: SpaceAttribution?
    /// 来源画布条目的五色徽章（I1，P2 final）：非 `.recyclable` 的条目在
    /// 预演 sheet 里**默认豁免**（C4 违约修复 —— 「数据·不属垃圾」项绝不
    /// 默认进清理集）。nil = 入口未携带徽章（快捷回收推荐项等树来源），
    /// 保持既有默认勾选行为。
    public let badge: BadgeKind?

    public init(id: UUID = UUID(), target: CleanupTarget,
                attribution: SpaceAttribution?,
                badge: BadgeKind? = nil) {
        self.id = id
        self.target = target
        self.attribution = attribution
        self.badge = badge
    }
}

public enum CleanupRehearsal {
    /// targets 与输出 1:1 同序；归因按路径首段匹配。
    /// `badgesByPath`（I1）：路径 → 徽章，由携带 CanvasEntry 的入口传入。
    public static func build(targets: [CleanupTarget],
                             attributions: [SpaceAttribution],
                             badgesByPath: [String: BadgeKind] = [:]) -> [RehearsalItem] {
        let byPath = Dictionary(attributions.map { ($0.paths.first ?? "", $0) },
                                uniquingKeysWith: { first, _ in first })
        return targets.map { target in
            RehearsalItem(target: target,
                          attribution: byPath[target.url.path],
                          badge: badgesByPath[target.url.path])
        }
    }

    /// 预演行的默认豁免集（I1）：带非 `.recyclable` 徽章的条目路径 ——
    /// 「迁出/注意/数据·不属垃圾/不动」一律不默认勾选（C4）；无徽章
    /// （树来源推荐项）保持既有默认勾选。sheet 初始化与锁定测试共用。
    public static func defaultExemptedPaths(for items: [RehearsalItem]) -> Set<String> {
        Set(items.compactMap { item -> String? in
            guard let badge = item.badge, badge != .recyclable else { return nil }
            return item.target.url.path
        })
    }
}
