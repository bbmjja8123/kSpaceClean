// kWise/Tests/ResidueGroupingEngineTests.swift
import XCTest
import NaturalLanguage
import AppCatalogCore
@testable import kWise

final class ResidueGroupingEngineTests: XCTestCase {

    private func residue(_ type: ResidueType, _ path: String) -> ResidueFile {
        ResidueFile(url: URL(fileURLWithPath: path), type: type, sizeBytes: 100,
                    confidence: 0.9, description: "")
    }

    // MARK: - systemEmbeddingProvider 注入环境（I-1：真"解析后仍 nil"分支可测）

    private var originalProvider: (@Sendable () -> NLEmbedding?)!

    override func setUp() {
        super.setUp()
        originalProvider = ResidueGroupingEngine.systemEmbeddingProvider
    }

    override func tearDown() {
        ResidueGroupingEngine.systemEmbeddingProvider = originalProvider
        super.tearDown()
    }

    // MARK: - 规则遍

    func testRulePassMapsKnownTypes() {
        let groups = ResidueGroupingEngine.group([
            residue(.preferences, "/Users/x/Library/Preferences/com.a.plist"),
            residue(.caches, "/Users/x/Library/Caches/com.a"),
            residue(.launchAgent, "/Users/x/Library/LaunchAgents/com.a.plist"),
            residue(.appSupport, "/Users/x/Library/Application Support/com.a"),
            residue(.webKit, "/Users/x/Library/WebKit/com.a"),
            residue(.savedState, "/Users/x/Library/Saved Application State/com.a.savedState"),
        ], embedding: nil)

        let dict = Dictionary(uniqueKeysWithValues: groups.map { ($0.kind, $0.residues.count) })
        XCTAssertEqual(dict[.preferences], 1)
        XCTAssertEqual(dict[.caches], 1)
        XCTAssertEqual(dict[.launchAgents], 1)
        XCTAssertEqual(dict[.appData], 1)
        XCTAssertEqual(dict[.webData], 1)
        XCTAssertEqual(dict[.savedState], 1)
    }

    // MARK: - 降级分支（真 nil）

    /// `.appleScript` / `.log` 在规则遍中无映射（ruleKind 返回 nil），是验证
    /// "embedding 解析后仍 nil → 全落 other" 诚实降级的合法输入。
    /// （brief 原稿用 `.plugin`，但规则遍会把 plugin 归入 plugins，二者矛盾。）
    func testResolvedNilEmbeddingFallsAllToOther() {
        ResidueGroupingEngine.systemEmbeddingProvider = { nil }
        let groups = ResidueGroupingEngine.group([
            residue(.appleScript, "/nonstandard/odd/path.bin"),
            residue(.log, "/nonstandard/other/dir"),
        ], embedding: nil)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.kind, .other)
        XCTAssertEqual(groups.first?.residues.count, 2, "两条规则未覆盖 residue 都必须落 other")
    }

    /// 解析函数契约：注入非 nil 直接用（不查系统），nil 才走 provider。
    func testResolveEmbeddingUsesInjectedWithoutTouchingProvider() throws {
        ResidueGroupingEngine.systemEmbeddingProvider = {
            XCTFail("注入非 nil 时不得回退系统 embedding")
            return nil
        }
        guard let system = originalProvider() else {
            throw XCTSkip("本机无系统词向量，跳过注入直通用例")
        }
        XCTAssertTrue(ResidueGroupingEngine.resolveEmbedding(system) === system)
    }

    func testResolveEmbeddingReturnsNilWhenProviderNil() {
        ResidueGroupingEngine.systemEmbeddingProvider = { nil }
        XCTAssertNil(ResidueGroupingEngine.resolveEmbedding(nil))
    }

    // MARK: - embedding 正路径（注入手写向量，纯函数覆盖）

    /// 命中：路径组件质心与 caches 锚点质心同向 → 归入 caches。
    func testEmbeddingPassGroupsByAnchorSimilarity() {
        let cacheAnchors: Set<String> = ["cache", "caches", "缓存", "临时", "temp"]
        let kind = ResidueGroupingEngine.bestEmbeddingMatch(
            for: "/weird/dir/cache-dump.bin",
            vectorLookup: { word in
                if word == "cache" || word == "dump" { return [1.0, 0.0, 0.0] }
                return cacheAnchors.contains(word) ? [1.0, 0.0, 0.0] : nil
            })
        XCTAssertEqual(kind, .caches)
    }

    /// 低于阈值：组件与锚点正交（余弦 0 < 0.45）→ 不归组（调用方落 other）。
    func testEmbeddingPassBelowThresholdReturnsNil() {
        let cacheAnchors: Set<String> = ["cache", "caches", "缓存", "临时", "temp"]
        let kind = ResidueGroupingEngine.bestEmbeddingMatch(
            for: "/weird/dir/zzz.bin",
            vectorLookup: { word in
                if word == "zzz" { return [0.0, 1.0, 0.0] }
                return cacheAnchors.contains(word) ? [1.0, 0.0, 0.0] : nil
            })
        XCTAssertNil(kind)
    }

    /// I-3：混合维度（不同 embedding 串缓存等异常）→ 放弃归组而非给垃圾值。
    func testMixedDimensionVectorsAbortMatching() {
        let kind = ResidueGroupingEngine.bestEmbeddingMatch(
            for: "/a/cache-mix",
            vectorLookup: { word in word == "cache" ? [1.0, 0.0, 0.0] : [1.0, 0.0] })
        XCTAssertNil(kind)
    }

    func testCosineSimilarityHandlesDegenerateInput() {
        XCTAssertEqual(ResidueGroupingEngine.cosineSimilarity([1, 0], [0, 1]), 0.0)
        XCTAssertNil(ResidueGroupingEngine.cosineSimilarity([0, 0], [1, 1]))
        XCTAssertNil(ResidueGroupingEngine.cosineSimilarity([1, 0], [1, 0, 0]))
        XCTAssertEqual(ResidueGroupingEngine.cosineSimilarity([1, 0], [2, 0])!, 1.0, accuracy: 1e-9)
    }

    // MARK: - 不变量与输出形状

    func testFixedCategoryOrder() {
        let groups = ResidueGroupingEngine.group([
            residue(.savedState, "/a"),
            residue(.preferences, "/b"),
            residue(.caches, "/c"),
        ], embedding: nil)
        let order = groups.map(\.kind)
        XCTAssertEqual(order, ResidueGroupKind.allCases.filter { order.contains($0) },
                       "分组输出必须按 ResidueGroupKind.allCases 固定排序")
    }

    /// 任何 embedding 环境（系统可用 / 强制 nil）下，输入 residue 不得消失。
    func testNoResidueIsEverDropped() {
        let input = [
            residue(.appleScript, "/nonstandard/odd/path.bin"),
            residue(.log, "/Users/x/Library/Logs/com.a"),
            residue(.httpStorage, "/Users/x/Library/HTTPStorages/com.a"),
            residue(.preferences, "/Users/x/Library/Preferences/com.a.plist"),
        ]
        for provider: () -> NLEmbedding? in [originalProvider, { nil }] {
            ResidueGroupingEngine.systemEmbeddingProvider = provider
            let groups = ResidueGroupingEngine.group(input, embedding: nil)
            XCTAssertEqual(groups.reduce(0) { $0 + $1.residues.count }, input.count,
                           "每个输入 residue 必须恰好出现在一个分组里")
        }
    }

    func testEmptyInputYieldsEmptyOutput() {
        XCTAssertTrue(ResidueGroupingEngine.group([], embedding: nil).isEmpty)
    }
}
