// kWise/Features/AppUninstall/ResidueGroupingEngine.swift
//
// AI 语义分组引擎 (v2.6)：规则遍 + NLEmbedding 遍。纯内存、零网络。
import Foundation
import NaturalLanguage
import AppCatalogCore

enum ResidueGroupKind: String, CaseIterable {
    case preferences, caches, appData, webData, launchAgents, plugins, savedState, other

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

struct ResidueGroup: Identifiable {
    let kind: ResidueGroupKind
    let residues: [ResidueFile]
    var id: ResidueGroupKind { kind }
}

enum ResidueGroupingEngine {

    private static let embeddingCache = NSCache<NSString, NSArray>()

    /// 主入口：规则遍 + embedding 遍。`embedding` 可注入 mock（测试），
    /// nil 时尝试系统 zh/en 词向量，均不可用则全落 other。
    static func group(_ residues: [ResidueFile],
                      embedding: NLEmbedding?) -> [ResidueGroup] {
        let effective = embedding ?? NLEmbedding.wordEmbedding(for: .simplifiedChinese)
            ?? NLEmbedding.wordEmbedding(for: .english)

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
        // 未命中或 embedding 不可用 → 全落 other（诚实降级，绝不丢文件）。
        if let embedding = effective {
            for residue in unknowns {
                if let kind = bestEmbeddingMatch(for: residue.url.path, embedding: embedding) {
                    buckets[kind, default: []].append(residue)
                } else {
                    buckets[.other, default: []].append(residue)
                }
            }
        } else {
            buckets[.other, default: []].append(contentsOf: unknowns)
        }

        return ResidueGroupKind.allCases.compactMap { kind in
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
    private static func bestEmbeddingMatch(for path: String,
                                           embedding: NLEmbedding) -> ResidueGroupKind? {
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
                                            embedding: embedding) else { continue }
            if score >= threshold, score > (best?.score ?? -1) {
                best = (kind, score)
            }
        }
        return best?.kind
    }

    private static func averageCosine(components: [String],
                                      anchors: [String],
                                      embedding: NLEmbedding) -> Double? {
        let componentVectors = components.compactMap { vector(for: $0, embedding: embedding) }
        let anchorVectors = anchors.compactMap { vector(for: $0, embedding: embedding) }
        guard !componentVectors.isEmpty, !anchorVectors.isEmpty else { return nil }

        let componentCentroid = centroid(of: componentVectors)
        let anchorCentroid = centroid(of: anchorVectors)
        let dot = zip(componentCentroid, anchorCentroid).reduce(0.0) { $0 + $1.0 * $1.1 }
        let magA = (componentCentroid.reduce(0.0) { $0 + $1 * $1 }).squareRoot()
        let magB = (anchorCentroid.reduce(0.0) { $0 + $1 * $1 }).squareRoot()
        guard magA > 0, magB > 0 else { return nil }
        return dot / (magA * magB)
    }

    private static func vector(for word: String, embedding: NLEmbedding) -> [Double]? {
        let key = "\(word)" as NSString
        if let cached = embeddingCache.object(forKey: key) as? [Double] {
            return cached
        }
        guard let vector = embedding.vector(for: word.lowercased()) else { return nil }
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
