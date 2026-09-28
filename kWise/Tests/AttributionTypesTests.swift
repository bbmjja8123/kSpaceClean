import XCTest
@testable import kWise

final class AttributionTypesTests: XCTestCase {
    func testReclaimabilityCodableRoundTrip() throws {
        let cases: [Reclaimability] = [.recycles(expectedDays: 30),
                                        .resurrects(via: "tmutil deletelocalsnapshots"),
                                        .permanent, .uncertain]
        for original in cases {
            let data = try JSONEncoder().encode([original])
            let decoded = try JSONDecoder().decode([Reclaimability].self, from: data)
            XCTAssertEqual(decoded, [original], "\(original) must round-trip")
        }
    }

    func testReclaimabilityJSONShape() throws {
        let data = try JSONEncoder().encode(Reclaimability.recycles(expectedDays: 30))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["kind"] as? String, "recycles")
        XCTAssertEqual(object["expectedDays"] as? Int, 30)
    }

    func testReclaimabilityRejectsUnknownKind() {
        let data = Data(#"{"kind":"magic"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Reclaimability.self, from: data))
    }

    func testCauseCoversSpecTaxonomy() {
        // spec §4.1 的 14 类原因，缺一不可（golden 断言防手滑删 case）。
        XCTAssertEqual(Set(AttributionCause.allCases.map(\.rawValue)),
            ["cache", "snapshot", "developerCache", "aiModel", "chatFiles",
             "renderCache", "download", "archive", "backup", "log",
             "mailAttachment", "iOSBackup", "containerData", "unknown"])
    }

    func testSpaceAttributionFields() {
        let a = SpaceAttribution(
            scope: .fileTree, paths: ["/tmp/x"], bytes: 100,
            owner: .app(bundleID: "com.apple.dt.Xcode", appName: "Xcode"),
            cause: .developerCache, reclaim: .recycles(expectedDays: 30),
            confidence: .certain, source: .rule, ruleID: "xcode.derived-data",
            evidence: [Evidence(kind: .ruleCitation, textKey: "attr.ev.ruleCitation",
                                arguments: ["xcode.derived-data"])],
            lastModified: nil)
        XCTAssertEqual(a.ruleID, "xcode.derived-data")
        XCTAssertEqual(a.confidence, .certain)
    }
}
