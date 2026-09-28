// kWise/Features/Attribution/AttributionRuleEngine.swift
//
// L0 归因引擎（spec §4.5）。红线：
// - first-match-wins，语料数组顺序即优先级 —— 审计测试强制「具体规则在通配之前」。
// - 结论永远可引用：输出带 ruleID 与证据链，不存在无出处的断言。
// - 未匹配 = 诚实说不知道（.refused），绝不猜。
import Foundation

public struct AttributionRuleEngine: Sendable {
    public let corpus: AttributionRuleCorpus
    public let homeDirectory: String
    /// `bundleDir` 归属解析：输入「匹配前缀之后的第一段目录名」，nil 表示不认识。
    public let bundleDirOwnerResolver: @Sendable (String?) -> AttributionOwner?

    public init(corpus: AttributionRuleCorpus,
                homeDirectory: String,
                bundleDirOwnerResolver: @escaping @Sendable (String?) -> AttributionOwner?
                    = AttributionRuleEngine.defaultBundleDirOwner) {
        self.corpus = corpus
        self.homeDirectory = homeDirectory
        self.bundleDirOwnerResolver = bundleDirOwnerResolver
    }

    /// 疑似反向域名（如 com.apple.Safari）→ app 归属；否则 nil。
    public static func defaultBundleDirOwner(_ directoryName: String?) -> AttributionOwner? {
        guard let name = directoryName, !name.isEmpty else { return nil }
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return .app(bundleID: name, appName: nil)
    }

    public func attribute(results: [ScanResult]) -> [SpaceAttribution] {
        results.map { attributeOne($0) }
    }

    private func attributeOne(_ result: ScanResult) -> SpaceAttribution {
        for proposed in corpus.rules {
            guard let glob = proposed.match.pathGlob,
                  PathGlobMatcher.matches(path: result.path, glob: glob, home: homeDirectory)
            else { continue }
            return matched(proposed, result: result, glob: glob)
        }
        // 未匹配 —— 诚实拒答（spec §5 拒答清单的原料）。
        return SpaceAttribution(
            scope: .fileTree, paths: [result.path], bytes: result.fileSize,
            owner: .unknown, cause: .unknown, reclaim: .uncertain,
            confidence: .refused, source: .unattributed, ruleID: nil,
            evidence: [], lastModified: result.modificationDate)
    }

    private func matched(_ proposed: AttributionRule, result: ScanResult,
                         glob: String) -> SpaceAttribution {
        let owner = resolveOwner(proposed.owner, path: result.path, glob: glob)
        var evidence: [Evidence] = [
            Evidence(kind: .pathPattern, textKey: "attr.ev.pathPattern", arguments: [glob]),
        ]
        let ownerDisplay: String?
        switch owner {
        case .app(let bundleID, let appName):
            ownerDisplay = appName ?? bundleID
        case .system:
            ownerDisplay = "macOS"
        case .user, .unknown:
            ownerDisplay = nil
        }
        if let ownerDisplay {
            evidence.append(Evidence(kind: .ownerApp, textKey: "attr.ev.ownerApp",
                                     arguments: [ownerDisplay]))
        }
        evidence.append(Evidence(kind: .ruleCitation, textKey: "attr.ev.ruleCitation",
                                 arguments: [proposed.id]))
        // lastModified 证据恒在（证据链顺序固定）。日期未知时 arguments 为空，
        // UI 按 lastModified == nil 渲染「未知」；不得因缺日期丢掉证据环节。
        evidence.append(Evidence(kind: .lastModified, textKey: "attr.ev.lastModified",
                                 arguments: result.modificationDate.map {
                                     [Self.evidenceDateFormatter.string(from: $0)]
                                 } ?? []))
        return SpaceAttribution(
            scope: .fileTree, paths: [result.path], bytes: result.fileSize,
            owner: owner, cause: proposed.cause, reclaim: proposed.reclaim,
            confidence: .certain, source: .rule, ruleID: proposed.id,
            evidence: evidence, lastModified: result.modificationDate)
    }

    private func resolveOwner(_ spec: AttributionOwnerSpec, path: String,
                              glob: String) -> AttributionOwner {
        switch spec {
        case .app(let bundleID, let appName):
            return .app(bundleID: bundleID, appName: appName)
        case .system:
            return .system
        case .user:
            return .user
        case .bundleDir:
            let component = Self.firstComponent(afterPrefix: matchedPrefix(of: glob),
                                                in: path)
            return bundleDirOwnerResolver(component) ?? .unknown
        }
    }

    /// glob 去掉尾部 `/**` 后的稳定目录前缀（~/ 与 home 展开已在 matcher 内完成，
    /// 这里复用同一展开规则）。
    private func matchedPrefix(of glob: String) -> String {
        let expanded = PathGlobMatcher.expandTilde(glob, home: homeDirectory)
        if expanded.hasSuffix("/**") {
            return String(expanded.dropLast(3))
        }
        return expanded
    }

    private static func firstComponent(afterPrefix prefix: String, in path: String) -> String? {
        guard path.hasPrefix(prefix) else { return nil }
        let remainder = path.dropFirst(prefix.count)
        let trimmed = remainder.hasPrefix("/") ? remainder.dropFirst() : remainder
        let first = trimmed.split(separator: "/").first
        return first.map(String.init)
    }

    /// 证据参数是面向人读的字符串；用固定 ISO8601 保证测试确定性，
    /// UI 层如需本地化时间可基于 `lastModified` 重排。
    static let evidenceDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
