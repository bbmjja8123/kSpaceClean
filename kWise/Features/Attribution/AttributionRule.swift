// kWise/Features/Attribution/AttributionRule.swift
//
// 归因语料的模型与加载（spec §4.4）。语料是产品资产、用户可查（信任契约
// 「规则开放」的实体），因此：
// - schemaVersion 向前守卫：新版本语料 + 旧版本 App → 明确报错，不静默错配。
// - 一切文案走 xcstrings key（notesKey），语料文件本身不含自然语言句子。
import Foundation

public struct AttributionRuleMatch: Equatable, Sendable, Codable {
    public let pathGlob: String?
    public init(pathGlob: String?) { self.pathGlob = pathGlob }
}

public enum AttributionOwnerSpec: Equatable, Sendable {
    case app(bundleID: String, appName: String?)
    case system
    case user
    /// 由路径中最近的疑似 bundleID 目录解析归属（如 ~/Library/Caches/<bundleID>/）。
    case bundleDir
}

extension AttributionOwnerSpec: Codable {
    private enum CodingKeys: String, CodingKey { case kind, bundleID, appName }
    private enum Kind: String, Codable { case app, system, user, bundleDir }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .app:
            self = .app(bundleID: try container.decode(String.self, forKey: .bundleID),
                        appName: try container.decodeIfPresent(String.self, forKey: .appName))
        case .system: self = .system
        case .user: self = .user
        case .bundleDir: self = .bundleDir
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let bundleID, let appName):
            try container.encode(Kind.app, forKey: .kind)
            try container.encode(bundleID, forKey: .bundleID)
            try container.encodeIfPresent(appName, forKey: .appName)
        case .system: try container.encode(Kind.system, forKey: .kind)
        case .user: try container.encode(Kind.user, forKey: .kind)
        case .bundleDir: try container.encode(Kind.bundleDir, forKey: .kind)
        }
    }
}

public struct AttributionRule: Equatable, Sendable {
    public let id: String
    public let match: AttributionRuleMatch
    public let owner: AttributionOwnerSpec
    public let cause: AttributionCause
    public let reclaim: Reclaimability
    public let notesKey: String
}

// 语料 JSON 反序列化（AttributionRuleCorpus.load 的 Wire 结构）要求规则本身可解码；
// 所有成员均已 Codable，逐字段合成。
extension AttributionRule: Codable {}

public struct AttributionRuleCorpus: Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public enum LoadError: Error, Equatable {
        case unsupportedSchemaVersion(found: Int)
    }

    public let schemaVersion: Int
    public let rules: [AttributionRule]

    public init(schemaVersion: Int, rules: [AttributionRule]) {
        self.schemaVersion = schemaVersion
        self.rules = rules
    }

    public static func load(from data: Data) throws -> AttributionRuleCorpus {
        struct Wire: Codable {
            let schemaVersion: Int
            let rules: [AttributionRule]
        }
        let wire = try JSONDecoder().decode(Wire.self, from: data)
        guard wire.schemaVersion <= currentSchemaVersion else {
            throw LoadError.unsupportedSchemaVersion(found: wire.schemaVersion)
        }
        return AttributionRuleCorpus(schemaVersion: wire.schemaVersion, rules: wire.rules)
    }
}
