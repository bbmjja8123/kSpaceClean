import XCTest
@testable import kWise

final class AttributionRuleTests: XCTestCase {
    private let sampleJSON = Data(#"""
    {"schemaVersion": 1, "rules": [{
        "id": "xcode.derived-data",
        "match": {"pathGlob": "~/Library/Developer/Xcode/DerivedData/**"},
        "owner": {"kind": "app", "bundleID": "com.apple.dt.Xcode", "appName": "Xcode"},
        "cause": "developerCache",
        "reclaim": {"kind": "recycles", "expectedDays": 30},
        "notesKey": "attr.notes.xcode.derived-data"}]}
    """#.utf8)

    func testLoadSampleCorpus() throws {
        let corpus = try AttributionRuleCorpus.load(from: sampleJSON)
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.rules.count, 1)
        let rule = try XCTUnwrap(corpus.rules.first)
        XCTAssertEqual(rule.id, "xcode.derived-data")
        XCTAssertEqual(rule.owner, .app(bundleID: "com.apple.dt.Xcode", appName: "Xcode"))
        XCTAssertEqual(rule.cause, .developerCache)
        XCTAssertEqual(rule.reclaim, .recycles(expectedDays: 30))
    }

    func testBundleDirOwnerDecodes() throws {
        let json = Data(#"{"schemaVersion":1,"rules":[{"id":"c","match":{"pathGlob":"~/Library/Caches/**"},"owner":{"kind":"bundleDir"},"cause":"cache","reclaim":{"kind":"recycles","expectedDays":3},"notesKey":"attr.notes.c"}]}"#.utf8)
        let corpus = try AttributionRuleCorpus.load(from: json)
        XCTAssertEqual(corpus.rules.first?.owner, .bundleDir)
    }

    func testNewerSchemaVersionThrows() {
        let json = Data(#"{"schemaVersion": 999, "rules": []}"#.utf8)
        XCTAssertThrowsError(try AttributionRuleCorpus.load(from: json)) { error in
            guard case AttributionRuleCorpus.LoadError.unsupportedSchemaVersion(let found) = error else {
                return XCTFail("expected unsupportedSchemaVersion, got \(error)")
            }
            XCTAssertEqual(found, 999)
        }
    }
}

// MARK: - 语料审计（Task 4）

extension AttributionRuleTests {

    /// 语料 JSON 的源码树位置 —— 审计读源文件，保证 CI 与本机同判。
    private func corpusData() throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // kWise/
            .appendingPathComponent("Resources/attribution_rules.json")
        return try Data(contentsOf: url)
    }

    private func localizationCatalog() throws -> [String: [String: String]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
        // xcstrings 条目形如 {"extractionState": ..., "localizations": {lang: {stringUnit: ...}}}，
        // 需先解出 localizations 层（brief 初稿直接把条目当 lang→Unit 映射，会撞上 extractionState）。
        struct Catalog: Decodable { let strings: [String: Entry] }
        struct Entry: Decodable { let localizations: [String: Unit]? }
        struct Unit: Decodable { struct SU: Decodable { let value: String? }; let stringUnit: SU? }
        let decoded = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        var out: [String: [String: String]] = [:]
        for (key, entry) in decoded.strings {
            var values: [String: String] = [:]
            for (lang, unit) in entry.localizations ?? [:] {
                if let v = unit.stringUnit?.value { values[lang] = v }
            }
            out[key] = values
        }
        return out
    }

    func testCorpusIntegrity() throws {
        let corpus = try AttributionRuleCorpus.load(from: try corpusData())
        XCTAssertEqual(corpus.schemaVersion, AttributionRuleCorpus.currentSchemaVersion)
        XCTAssertGreaterThanOrEqual(corpus.rules.count, 16, "第一批语料不得少于 16 条")
        let ids = corpus.rules.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "规则 id 必须唯一")
        let globs = corpus.rules.compactMap(\.match.pathGlob)
        XCTAssertEqual(Set(globs).count, globs.count, "重复 glob = 死规则")
        for rule in corpus.rules {
            XCTAssertFalse(rule.id.isEmpty)
            XCTAssertNotNil(rule.match.pathGlob, "P0 语料全部为路径规则")
            XCTAssertEqual(rule.notesKey, "attr.notes.\(rule.id)",
                           "notesKey 必须遵循 attr.notes.<id> 约定")
        }
        // 优先级：具体规则必须在通配的 caches.app-generic 之前（first-match-wins）。
        let genericIndex = try XCTUnwrap(ids.firstIndex(of: "caches.app-generic"))
        for specific in ["wechat.files", "qq.files", "docker.disk-image"] {
            let index = try XCTUnwrap(ids.firstIndex(of: specific))
            XCTAssertLessThan(index, genericIndex,
                              "\(specific) 必须排在通配规则之前，否则永不被命中")
        }
    }

    func testEveryRuleCopyIsTrilingual() throws {
        let corpus = try AttributionRuleCorpus.load(from: try corpusData())
        let catalog = try localizationCatalog()
        var required = corpus.rules.map(\.notesKey)
        required += ["attr.ev.pathPattern", "attr.ev.ownerApp",
                     "attr.ev.ruleCitation", "attr.ev.lastModified"]
        for key in required {
            let langs = try XCTUnwrap(catalog[key], "missing xcstrings key \(key)")
            for lang in ["en", "zh-Hans", "ja"] {
                XCTAssertNotNil(langs[lang], "\(key) 缺少 \(lang) 译文")
            }
        }
    }
}
