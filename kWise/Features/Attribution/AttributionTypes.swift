// kWise/Features/Attribution/AttributionTypes.swift
//
// 归因引擎核心类型（spec §4.1）。设计红线：
// - 每条输出必须能回答「谁拥有 / 为什么在这 / 删了会不会回来」与
//   「这个结论怎么来的」（source + confidence）。
// - `reclaim == .uncertain` 的项永远不进清理建议，只进拒答清单。
import Foundation

public enum AttributionScope: String, Codable, Sendable {
    /// 文件树层：有具体路径。
    case fileTree
    /// 卷层：APFS 快照 / 系统保留空间，无文件路径。
    case volumeLayer
}

/// ① 归属判定。
public enum AttributionOwner: Equatable, Sendable {
    case app(bundleID: String, appName: String?)
    case system
    case user
    case unknown
}

/// ② 存在原因。rawValue 同时是语料 JSON 与本地化 key 的后缀（attr.cause.<raw>）。
public enum AttributionCause: String, Codable, Sendable, CaseIterable {
    case cache
    case snapshot
    case developerCache
    case aiModel
    case chatFiles
    case renderCache
    case download
    case archive
    case backup
    case log
    case mailAttachment
    case iOSBackup
    case containerData
    case unknown
}

/// ③ 可回收性 —— 本产品的差异化核心（全品类无人做「删了会不会回来」）。
public enum Reclaimability: Equatable, Sendable {
    /// 会回来：缓存类，预期 N 天后重建。
    case recycles(expectedDays: Int)
    /// 会复活：直接删没用，`via` 给出正确解法（如 tmutil 引导）。
    case resurrects(via: String)
    /// 不会回来：真空间（旧导出 / 安装包）。
    case permanent
    /// 不敢判 → 拒答清单，绝不进清理建议。
    case uncertain
}

extension Reclaimability: Codable {
    private enum CodingKeys: String, CodingKey { case kind, expectedDays, via }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "recycles":
            self = .recycles(expectedDays: try container.decodeIfPresent(Int.self, forKey: .expectedDays) ?? 30)
        case "resurrects":
            self = .resurrects(via: try container.decodeIfPresent(String.self, forKey: .via) ?? "tmutil")
        case "permanent":
            self = .permanent
        case "uncertain":
            self = .uncertain
        default:
            let raw = (try? container.decode(String.self, forKey: .kind)) ?? "nil"
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container,
                debugDescription: "unknown reclaim kind: \(raw)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .recycles(let days):
            try container.encode("recycles", forKey: .kind)
            try container.encode(days, forKey: .expectedDays)
        case .resurrects(let via):
            try container.encode("resurrects", forKey: .kind)
            try container.encode(via, forKey: .via)
        case .permanent:
            try container.encode("permanent", forKey: .kind)
        case .uncertain:
            try container.encode("uncertain", forKey: .kind)
        }
    }
}

/// 置信度三档（spec §4.5 渲染契约：确定 / 推测 / 不知道）。
public enum AttributionConfidence: String, Codable, Sendable {
    /// 规则命中，可引用 ruleID —— P0 唯一的正常产出。
    case certain
    /// 模型推测（P0 不产出；L1/L2 预留）。
    case probable
    /// 没有规则能判断 → 拒答清单。
    case refused
}

/// 来源标注 —— HIG GenAI「标注 AI 生成」的落地形式。
public enum AttributionSource: String, Codable, Sendable {
    case rule
    case nlEmbedding
    case createML
    case fmTagging
    /// 无来源（未匹配任何规则）。
    case unattributed
}

public enum EvidenceKind: String, Codable, Sendable {
    case pathPattern
    case ownerApp
    case ruleCitation
    case lastModified
}

/// 理由链的一环。`textKey` 指向 xcstrings（可含 %@ / %lld），
/// 禁止在代码里拼接英文/中文句子 —— 文案必须可审计、可翻译。
public struct Evidence: Equatable, Sendable {
    public let kind: EvidenceKind
    public let textKey: String
    public let arguments: [String]

    public init(kind: EvidenceKind, textKey: String, arguments: [String] = []) {
        self.kind = kind
        self.textKey = textKey
        self.arguments = arguments
    }
}

public struct SpaceAttribution: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let scope: AttributionScope
    public let paths: [String]
    public let bytes: Int64
    public let owner: AttributionOwner
    public let cause: AttributionCause
    public let reclaim: Reclaimability
    public let confidence: AttributionConfidence
    public let source: AttributionSource
    public let ruleID: String?
    public let evidence: [Evidence]
    public let lastModified: Date?

    public init(id: UUID = UUID(),
                scope: AttributionScope,
                paths: [String],
                bytes: Int64,
                owner: AttributionOwner,
                cause: AttributionCause,
                reclaim: Reclaimability,
                confidence: AttributionConfidence,
                source: AttributionSource,
                ruleID: String?,
                evidence: [Evidence],
                lastModified: Date?) {
        self.id = id
        self.scope = scope
        self.paths = paths
        self.bytes = bytes
        self.owner = owner
        self.cause = cause
        self.reclaim = reclaim
        self.confidence = confidence
        self.source = source
        self.ruleID = ruleID
        self.evidence = evidence
        self.lastModified = lastModified
    }
}
