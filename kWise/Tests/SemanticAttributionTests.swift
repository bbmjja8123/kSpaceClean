import XCTest
import NaturalLanguage
@testable import kWise

final class SemanticAttributionTests: XCTestCase {
    // MARK: - 纯函数：路径词元化

    func testPathTokensStripsNoiseAndShortFragments() {
        let tokens = SentenceEmbeddingAttributionProvider.pathTokens(
            "/Users/x/Library/Containers/com.tencent.xinWeChat/Data/Files/a1")
        XCTAssertFalse(tokens.contains("users"))
        XCTAssertFalse(tokens.contains("library"))
        XCTAssertTrue(tokens.contains("tencent"), "bundle 反域名段保留")
        XCTAssertTrue(tokens.contains("xinwechat"))
        XCTAssertFalse(tokens.contains("a"), "单字符词元丢弃")
    }

    func testMaxCosineDistanceIsCalibratable() {
        XCTAssertEqual(SentenceEmbeddingAttributionProvider.maxCosineDistance, 0.85)
    }

    // MARK: - 真实 provider（环境可用时）

    func testProviderReturnsNilOrCauseNeverCrashes() throws {
        guard NLEmbedding.sentenceEmbedding(for: .english) != nil else {
            throw XCTSkip("句向量资产不可用（CI/精简系统）——mock 路径已覆盖逻辑")
        }
        let provider = SentenceEmbeddingAttributionProvider()
        // 两种结果都合法：nil（低于阈值=拒答）或某个 cause——红线是绝不 crash。
        _ = provider.probableCause(for: "/Users/x/Library/Caches/com.apple.Safari/Cache.db")
    }

    // MARK: - Service 层升级管道（mock 驱动）

    private struct StubProvider: SemanticAttributionProviding {
        let cause: AttributionCause?
        func probableCause(for path: String) -> AttributionCause? { cause }
    }

    private func service(provider: SemanticAttributionProviding?) -> AttributionService {
        let corpus = AttributionRuleCorpus(schemaVersion: 1, rules: [])
        return AttributionService(
            engine: AttributionRuleEngine(corpus: corpus, homeDirectory: "/Users/t"),
            volumeReader: nil,
            rootURL: URL(fileURLWithPath: "/Users/t"),
            volumeUsedBytesProvider: { nil },
            semanticProvider: provider)
    }

    private func category(paths: [(String, Int64)]) -> [ScanCategory] {
        let results = paths.map {
            ScanResult(url: URL(fileURLWithPath: $0.0), path: $0.0, title: "x",
                       fileSize: $0.1, cleanType: .cache)
        }
        let action = ScanAction(actionID: "a", actionType: .cache, title: "a", results: results)
        let sub = ScanSubCategory(subCategoryID: "s", title: "s", actions: [action])
        return [ScanCategory(categoryID: "c", title: "c", subItems: [sub])]
    }

    func testRefusedUpgradesToProbableWhenProviderHits() async {
        let report = await service(provider: StubProvider(cause: .chatFiles))
            .attribute(categories: category(paths: [("/Users/t/mystery/chat.bin", 900_000_000)]))
        let refused = report.refused
        XCTAssertEqual(refused.count, 1)
        let item = refused[0]
        XCTAssertEqual(item.confidence, .probable, "provider 命中 → 升级为推测")
        XCTAssertEqual(item.source, .nlEmbedding)
        XCTAssertEqual(item.cause, .chatFiles)
        XCTAssertEqual(item.reclaim, .uncertain, "推测不改可回收性判定")
    }

    func testRefusedStaysRefusedWhenProviderMisses() async {
        let report = await service(provider: StubProvider(cause: nil))
            .attribute(categories: category(paths: [("/Users/t/mystery.bin", 900_000_000)]))
        XCTAssertEqual(report.refused[0].confidence, .refused)
        XCTAssertEqual(report.refused[0].source, .unattributed)
    }

    func testMatchedItemsNeverRoutedThroughProvider() async {
        // L0 命中的项不吃 L1——来源标注必须保持 .rule。
        let corpus = AttributionRuleCorpus(schemaVersion: 1, rules: [AttributionRule(
            id: "caches.app-generic", match: AttributionRuleMatch(pathGlob: "~/Library/Caches/**"),
            owner: .bundleDir, cause: .cache, reclaim: .recycles(expectedDays: 3),
            notesKey: "attr.notes.caches.app-generic")])
        let service = AttributionService(
            engine: AttributionRuleEngine(corpus: corpus, homeDirectory: "/Users/t"),
            volumeReader: nil, rootURL: URL(fileURLWithPath: "/Users/t"),
            volumeUsedBytesProvider: { nil },
            semanticProvider: StubProvider(cause: .aiModel))
        let report = await service.attribute(categories: category(paths: [
            ("/Users/t/Library/Caches/com.apple.Safari/x", 5_000_000)]))
        XCTAssertEqual(report.items[0].source, .rule)
        XCTAssertEqual(report.items[0].confidence, .certain)
    }
}
