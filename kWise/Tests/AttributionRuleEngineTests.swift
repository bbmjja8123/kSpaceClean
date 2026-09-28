import XCTest
@testable import kWise

final class AttributionRuleEngineTests: XCTestCase {
    private let home = "/Users/tester"

    /// 与语料等价的内存语料 —— 引擎测试不依赖 JSON 文件（Task 4 审计已管语料）。
    private func corpus(_ rules: [AttributionRule]) -> AttributionRuleCorpus {
        AttributionRuleCorpus(schemaVersion: 1, rules: rules)
    }

    private func rule(_ id: String, _ glob: String, owner: AttributionOwnerSpec,
                      cause: AttributionCause, reclaim: Reclaimability) -> AttributionRule {
        AttributionRule(id: id, match: AttributionRuleMatch(pathGlob: glob), owner: owner,
                        cause: cause, reclaim: reclaim, notesKey: "attr.notes.\(id)")
    }

    private func result(_ path: String, bytes: Int64,
                        modified: Date? = nil) -> ScanResult {
        ScanResult(url: URL(fileURLWithPath: path), path: path, title: "x",
                   fileSize: bytes, modificationDate: modified, cleanType: .cache)
    }

    func testDerivedDataMatchesXcodeRule() {
        let engine = AttributionRuleEngine(corpus: corpus([
            rule("xcode.derived-data", "~/Library/Developer/Xcode/DerivedData/**",
                 owner: .app(bundleID: "com.apple.dt.Xcode", appName: "Xcode"),
                 cause: .developerCache, reclaim: .recycles(expectedDays: 30)),
        ]), homeDirectory: home)
        let out = engine.attribute(results: [
            result("/Users/tester/Library/Developer/Xcode/DerivedData/App-abc/Build/x.o", bytes: 500)
        ])
        XCTAssertEqual(out.count, 1)
        let a = out[0]
        XCTAssertEqual(a.owner, .app(bundleID: "com.apple.dt.Xcode", appName: "Xcode"))
        XCTAssertEqual(a.cause, .developerCache)
        XCTAssertEqual(a.reclaim, .recycles(expectedDays: 30))
        XCTAssertEqual(a.confidence, .certain)
        XCTAssertEqual(a.source, .rule)
        XCTAssertEqual(a.ruleID, "xcode.derived-data")
        XCTAssertEqual(a.evidence.map(\.kind), [.pathPattern, .ownerApp, .ruleCitation, .lastModified])
        XCTAssertEqual(a.evidence[2].arguments, ["xcode.derived-data"])
    }

    func testBundleDirOwnerResolvedFromComponentAfterMatchedPrefix() {
        var resolved: String?
        let engine = AttributionRuleEngine(
            corpus: corpus([rule("caches.app-generic", "~/Library/Caches/**",
                                 owner: .bundleDir, cause: .cache,
                                 reclaim: .recycles(expectedDays: 3))]),
            homeDirectory: home,
            bundleDirOwnerResolver: { name in
                resolved = name
                return name.map { .app(bundleID: $0, appName: nil) }
            })
        let out = engine.attribute(results: [
            result("/Users/tester/Library/Caches/com.apple.Safari/Cache.db", bytes: 10)
        ])
        XCTAssertEqual(resolved, "com.apple.Safari", "必须取匹配前缀后的第一段")
        XCTAssertEqual(out[0].owner, .app(bundleID: "com.apple.Safari", appName: nil))
    }

    func testBundleDirFallbackToUnknownWhenResolverNil() {
        let engine = AttributionRuleEngine(
            corpus: corpus([rule("caches.app-generic", "~/Library/Caches/**",
                                 owner: .bundleDir, cause: .cache,
                                 reclaim: .recycles(expectedDays: 3))]),
            homeDirectory: home,
            bundleDirOwnerResolver: { _ in nil })
        let out = engine.attribute(results: [
            result("/Users/tester/Library/Caches/loose.file", bytes: 10)
        ])
        XCTAssertEqual(out[0].owner, .unknown)
        XCTAssertEqual(out[0].confidence, .certain, "匹配到规则仍是规则判定；owner 未知只影响 owner")
    }

    func testFirstMatchWinsByCorpusOrder() {
        let engine = AttributionRuleEngine(corpus: corpus([
            rule("specific", "~/Library/Caches/com.apple.Safari/**",
                 owner: .app(bundleID: "com.apple.Safari", appName: "Safari"),
                 cause: .cache, reclaim: .permanent),
            rule("generic", "~/Library/Caches/**",
                 owner: .bundleDir, cause: .cache, reclaim: .recycles(expectedDays: 3)),
        ]), homeDirectory: home)
        let out = engine.attribute(results: [
            result("/Users/tester/Library/Caches/com.apple.Safari/x", bytes: 1)
        ])
        XCTAssertEqual(out[0].ruleID, "specific", "语料顺序即优先级")
    }

    func testUnmatchedBigResultIsRefused() {
        let engine = AttributionRuleEngine(corpus: corpus([]), homeDirectory: home)
        let out = engine.attribute(results: [
            result("/Users/tester/mystery.bin", bytes: 999)
        ])
        let a = out[0]
        XCTAssertEqual(a.confidence, .refused)
        XCTAssertEqual(a.source, .unattributed)
        XCTAssertEqual(a.owner, .unknown)
        XCTAssertEqual(a.cause, .unknown)
        XCTAssertEqual(a.reclaim, .uncertain)
        XCTAssertTrue(a.evidence.isEmpty)
    }

    func testLastModifiedFlowsThrough() {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let engine = AttributionRuleEngine(corpus: corpus([
            rule("xcode.derived-data", "~/Library/Developer/Xcode/DerivedData/**",
                 owner: .app(bundleID: "com.apple.dt.Xcode", appName: nil),
                 cause: .developerCache, reclaim: .recycles(expectedDays: 30)),
        ]), homeDirectory: home)
        let out = engine.attribute(results: [
            result("/Users/tester/Library/Developer/Xcode/DerivedData/x", bytes: 1, modified: date)
        ])
        XCTAssertEqual(out[0].lastModified, date)
        XCTAssertEqual(out[0].evidence.last?.kind, .lastModified)
        XCTAssertFalse(out[0].evidence.last!.arguments.isEmpty,
                       "lastModified 证据必须带格式化参数")
    }

    func testDefaultBundleDirOwner() {
        XCTAssertEqual(AttributionRuleEngine.defaultBundleDirOwner("com.apple.Safari"),
                       .app(bundleID: "com.apple.Safari", appName: nil))
        XCTAssertNil(AttributionRuleEngine.defaultBundleDirOwner("NoDots"))
        XCTAssertNil(AttributionRuleEngine.defaultBundleDirOwner(nil))
        XCTAssertNil(AttributionRuleEngine.defaultBundleDirOwner("a..b"), "空段不是合法 bundleID")
    }
}
