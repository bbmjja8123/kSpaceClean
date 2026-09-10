// kWise/Features/AppUninstall/ResidueGroupingEngine.swift
//
// AI 语义分组引擎 (v2.6)：规则遍 + NLEmbedding 遍。纯内存、零网络。
import Foundation
import NaturalLanguage
import AppCatalogCore

public enum ResidueGroupKind: String, CaseIterable {
    case preferences, caches, appData, webData, launchAgents, plugins, savedState, other

    /// 分组展示名（本地化键与中文 copy 一并维护，见 Localizable.xcstrings）。
    var title: String {
        switch self {
        case .preferences: return "偏好设置"
        case .caches: return "缓存数据"
        case .appData: return "应用数据"
        case .webData: return "网页数据"
        case .launchAgents: return "启动项"
        case .plugins: return "插件与面板"
        case .savedState: return "窗口状态"
        case .other: return "其他"
        }
    }

    /// SF Symbol 名，用于分组行首图标。
    var icon: String {
        switch self {
        case .preferences: return "gearshape"
        case .caches: return "cpu"
        case .appData: return "shippingbox"
        case .webData: return "globe"
        case .launchAgents: return "power"
        case .plugins: return "puzzlepiece"
        case .savedState: return "rectangle.stack"
        case .other: return "shippingbox"
        }
    }

    /// NLEmbedding 归组的锚点词。
    var anchorWords: [String] {
        switch self {
        case .preferences: return ["preferences", "plist", "设置", "偏好", "config"]
        case .caches: return ["cache", "caches", "缓存", "临时", "temp"]
        case .appData: return ["support", "数据", "data", "documents", "container"]
        case .webData: return ["webkit", "cookie", "storage", "网页", "localstorage"]
        case .launchAgents: return ["agent", "daemon", "launch", "启动", "login"]
        case .plugins: return ["plugin", "prefpane", "插件", "panel"]
        case .savedState: return ["saved", "state", "状态", "windows"]
        case .other: return []
        }
    }
}

/// 一个语义分组的产物（kind + 组内残留）。public 供 ViewModel 的
/// 面板分组 API 跨文件暴露（详情面板 / 测试同模块使用）。
public struct ResidueGroup: Identifiable {
    public let kind: ResidueGroupKind
    public let residues: [ResidueFile]
    public var id: ResidueGroupKind { kind }

    public init(kind: ResidueGroupKind, residues: [ResidueFile]) {
        self.kind = kind
        self.residues = residues
    }
}

enum ResidueGroupingEngine {

    private static let embeddingCache = NSCache<NSString, NSArray>()

    /// 系统 embedding 提供器。生产路径尝试 zh → en 词向量；
    /// 测试可临时替换（如 `{ nil }`）以强制"解析后仍 nil"的真降级分支。
    /// 测试须在 tearDown 恢复原值。
    static var systemEmbeddingProvider: @Sendable () -> NLEmbedding? = {
        NLEmbedding.wordEmbedding(for: .simplifiedChinese)
            ?? NLEmbedding.wordEmbedding(for: .english)
    }

    /// 解析 embedding：注入非 nil 直接用；nil 时走 ``systemEmbeddingProvider``。
    static func resolveEmbedding(_ injected: NLEmbedding?) -> NLEmbedding? {
        injected ?? systemEmbeddingProvider()
    }

    /// 主入口：规则遍 + embedding 遍。`embedding` 可注入 mock（测试）；
    /// 解析后仍为 nil（真"不可用"）→ 规则未覆盖的全落 other，绝不丢文件。
    static func group(_ residues: [ResidueFile],
                      embedding: NLEmbedding?) -> [ResidueGroup] {
        let lookup: ((String) -> [Double]?)? = resolveEmbedding(embedding).map { embedding in
            { Self.vector(for: $0, embedding: embedding) }
        }

        var buckets: [ResidueGroupKind: [ResidueFile]] = [:]
        var unknowns: [ResidueFile] = []

        for residue in residues {
            guard let kind = ruleKind(for: residue) else {
                unknowns.append(residue)
                continue
            }
            buckets[kind, default: []].append(residue)
        }

        // embedding 遍：未知路径按组件词向量与锚点余弦相似度归组；
        // 未命中或 embedding 不可用 → 全落 other（诚实降级）。
        for residue in unknowns {
            let kind = lookup.flatMap { bestEmbeddingMatch(for: residue.url.path, vectorLookup: $0) }
            buckets[kind ?? .other, default: []].append(residue)
        }

        return buildGroups(from: buckets)
    }

    private static func buildGroups(from buckets: [ResidueGroupKind: [ResidueFile]]) -> [ResidueGroup] {
        ResidueGroupKind.allCases.compactMap { kind in
            guard let items = buckets[kind], !items.isEmpty else { return nil }
            return ResidueGroup(kind: kind, residues: items)
        }
    }

    /// 规则遍：ResidueType → kind。nil = 规则未覆盖，交给 embedding。
    private static func ruleKind(for residue: ResidueFile) -> ResidueGroupKind? {
        switch residue.type {
        case .preferences: return .preferences
        case .caches: return .caches
        case .appSupport, .groupContainer, .container: return .appData
        case .webKit, .cookie: return .webData
        case .launchAgent, .launchDaemon, .startupItem: return .launchAgents
        case .plugin, .prefPane: return .plugins
        case .savedState: return .savedState
        default: return nil
        }
    }

    /// 路径组件词 → 平均向量 vs 类目锚点平均向量，取最高余弦且 ≥0.45。
    /// `vectorLookup` 注入（真 NLEmbedding 由 ``vector(for:embedding:)`` 包装），
    /// 纯函数、可离线测试命中归组 / 低于阈值 / 混合维度三种走向。
    static func bestEmbeddingMatch(for path: String,
                                   vectorLookup: (String) -> [Double]?) -> ResidueGroupKind? {
        let components = path
            .split(whereSeparator: { "/-_ .".contains($0) })
            .map(String.init)
            .filter { $0.count >= 3 }
        guard !components.isEmpty else { return nil }

        let threshold = 0.45
        var best: (kind: ResidueGroupKind, score: Double)?
        for kind in ResidueGroupKind.allCases where !kind.anchorWords.isEmpty {
            guard let score = averageCosine(components: components,
                                            anchors: kind.anchorWords,
                                            vectorLookup: vectorLookup) else { continue }
            if score >= threshold, score > (best?.score ?? -1) {
                best = (kind, score)
            }
        }
        return best?.kind
    }

    /// 组件质心 vs 锚点质心的余弦相似度。任一侧无向量或出现混合维度
    /// （不同 embedding 串缓存等异常）→ nil，宁可放弃归组也不给垃圾值。
    static func averageCosine(components: [String],
                              anchors: [String],
                              vectorLookup: (String) -> [Double]?) -> Double? {
        let componentVectors = components.compactMap(vectorLookup)
        let anchorVectors = anchors.compactMap(vectorLookup)
        guard !componentVectors.isEmpty, !anchorVectors.isEmpty else { return nil }
        let dim = componentVectors[0].count
        guard componentVectors.allSatisfy({ $0.count == dim }),
              anchorVectors.allSatisfy({ $0.count == dim }) else { return nil }

        let componentCentroid = centroid(of: componentVectors)
        let anchorCentroid = centroid(of: anchorVectors)
        return cosineSimilarity(componentCentroid, anchorCentroid)
    }

    /// 两个等长向量的余弦相似度；零向量或维度不一致 → nil。
    static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count else { return nil }
        let dot = zip(a, b).reduce(0.0) { $0 + $1.0 * $1.1 }
        let magA = (a.reduce(0.0) { $0 + $1 * $1 }).squareRoot()
        let magB = (b.reduce(0.0) { $0 + $1 * $1 }).squareRoot()
        guard magA > 0, magB > 0 else { return nil }
        return dot / (magA * magB)
    }

    private static func vector(for word: String, embedding: NLEmbedding) -> [Double]? {
        let lowered = word.lowercased()
        // 缓存 key 带 embedding 身份前缀（zh/en/mock 词向量互不串缓存），
        // 且与查询词同用小写，避免 "Cache" 写入 / "cache" 查询的命中失败。
        let key = "\(ObjectIdentifier(embedding).hashValue)|\(lowered)" as NSString
        if let cached = embeddingCache.object(forKey: key) as? [Double] {
            return cached
        }
        guard let vector = embedding.vector(for: lowered) else { return nil }
        embeddingCache.setObject(vector as NSArray, forKey: key)
        return vector
    }

    private static func centroid(of vectors: [[Double]]) -> [Double] {
        guard !vectors.isEmpty else { return [] }
        let dim = vectors[0].count
        var sum = [Double](repeating: 0, count: dim)
        for v in vectors {
            for i in 0..<dim { sum[i] += v[i] }
        }
        return sum.map { $0 / Double(vectors.count) }
    }
}
