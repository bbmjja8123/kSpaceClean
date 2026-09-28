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
