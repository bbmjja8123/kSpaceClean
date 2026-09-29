// kWise/Features/Attribution/SemanticAttribution.swift
//
// L1 语义归因（spec §4.5 第二层）。红线：
// - 只在 L0 未命中后调用；命中阈值以下返回 nil（调用方保持 refused）——绝不猜。
// - 推测产物 confidence = .probable / source = .nlEmbedding / reclaim 不变
//   （.uncertain）——推测不产生清理建议。
// - 样本短语表与语料规则的 cause 分类一一呼应；全英文（句向量英文资产最全），
//   路径先词元化（去框架噪音词）再拼回空格句。
import Foundation
import NaturalLanguage

public protocol SemanticAttributionProviding: Sendable {
    func probableCause(for path: String) -> AttributionCause?
}

public struct SentenceEmbeddingAttributionProvider: SemanticAttributionProviding {

    /// 原因 → 样本短语（英文，路径词元域）。阈值与样本表是真机校准点（P0 验收）。
    static let samplePhrases: [AttributionCause: [String]] = [
        .cache: ["cache temporary files app cache", "cached data browser cache"],
        .developerCache: ["developer build intermediates derived data xcode", "simulator caches device support"],
        .chatFiles: ["chat message attachments wechat files", "instant messaging received files"],
        .aiModel: ["machine learning model weights local ai models"],
        .log: ["log files diagnostics crash reports"],
        .mailAttachment: ["mail attachments email files"],
        .iOSBackup: ["iphone ipad device backup files mobile sync"],
        .renderCache: ["video render files media cache editing projects"],
        .download: ["downloaded installer files downloads"],
        .archive: ["compressed archive zip disk image"],
        .backup: ["backup snapshots system reserved"],
        .containerData: ["app container application support data"],
        .snapshot: ["time machine local snapshot"],
        .unknown: [],
    ]

    /// cosine 距离阈值（0=同向，2=反向）。真实机器上用语料路径校准。
    public static let maxCosineDistance = 0.85

    /// 词元化时剔除的框架噪音词——每条路径都有，无判别力。
    static let noiseTokens: Set<String> = [
        "users", "library", "containers", "data", "application",
        "support", "group", "private", "var", "tmp",
    ]

    public init() {}

    public func probableCause(for path: String) -> AttributionCause? {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }
        let tokens = Self.pathTokens(path)
        guard !tokens.isEmpty else { return nil }
        let sentence = tokens.joined(separator: " ")
        var best: (cause: AttributionCause, distance: NLDistance)?
        for (cause, phrases) in Self.samplePhrases where !phrases.isEmpty {
            for phrase in phrases {
                let distance = embedding.distance(between: sentence, and: phrase,
                                                  distanceType: .cosine)
                if best == nil || distance < best!.distance {
                    best = (cause, distance)
                }
            }
        }
        guard let best, best.distance <= Self.maxCosineDistance else { return nil }
        return best.cause
    }

    /// 路径 → 词元：非字母数字折成空格、丢单字符与噪音词。
    static func pathTokens(_ path: String) -> [String] {
        let flattened = path.lowercased().map { char -> Character in
            (char.isLetter || char.isNumber) ? char : " "
        }.reduce(into: "") { $0.append($1) }
        return flattened
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 && !Self.noiseTokens.contains($0) }
    }
}
