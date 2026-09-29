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

    public init(id: UUID = UUID(), target: CleanupTarget, attribution: SpaceAttribution?) {
        self.id = id
        self.target = target
        self.attribution = attribution
    }
}

public enum CleanupRehearsal {
    /// targets 与输出 1:1 同序；归因按路径首段匹配。
    public static func build(targets: [CleanupTarget],
                             attributions: [SpaceAttribution]) -> [RehearsalItem] {
        let byPath = Dictionary(attributions.map { ($0.paths.first ?? "", $0) },
                                uniquingKeysWith: { first, _ in first })
        return targets.map { target in
            RehearsalItem(target: target, attribution: byPath[target.url.path])
        }
    }
}
