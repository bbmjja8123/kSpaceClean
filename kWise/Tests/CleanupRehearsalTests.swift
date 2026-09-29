import XCTest
@testable import kWise

final class CleanupRehearsalTests: XCTestCase {
    private func target(_ path: String, size: Int64 = 100) -> CleanupTarget {
        CleanupTarget(url: URL(fileURLWithPath: path), size: size, risk: .recommended)
    }

    private func attribution(path: String, cause: AttributionCause = .cache) -> SpaceAttribution {
        SpaceAttribution(scope: .fileTree, paths: [path], bytes: 100,
                         owner: .app(bundleID: "com.x", appName: nil), cause: cause,
                         reclaim: .recycles(expectedDays: 3), confidence: .certain,
                         source: .rule, ruleID: "caches.app-generic", evidence: [], lastModified: nil)
    }

    func testOneToOneSameOrderContract() {
        let targets = [target("/a"), target("/b"), target("/c")]
        let items = CleanupRehearsal.build(targets: targets, attributions: [])
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map(\.target.url.path), ["/a", "/b", "/c"],
                       "预演与执行必须逐项一致（spec §10 P1 验收）")
        XCTAssertTrue(items.allSatisfy { $0.attribution == nil })
    }

    func testAttributionJoinedByPath() {
        let targets = [target("/Users/t/Library/Caches/Safari/x")]
        let items = CleanupRehearsal.build(
            targets: targets, attributions: [attribution(path: "/Users/t/Library/Caches/Safari/x")])
        XCTAssertEqual(items[0].attribution?.ruleID, "caches.app-generic")
        XCTAssertEqual(items[0].attribution?.cause, .cache)
    }

    func testRefusedAttributionStillShownHonestly() {
        // 拒答项被用户手动勾选时，预演必须如实显示「这是推测/不敢判」而不是装作有依据。
        let refused = SpaceAttribution(scope: .fileTree, paths: ["/m"], bytes: 1,
                                       owner: .unknown, cause: .unknown,
                                       reclaim: .uncertain, confidence: .refused,
                                       source: .unattributed, ruleID: nil,
                                       evidence: [], lastModified: nil)
        let items = CleanupRehearsal.build(targets: [target("/m")], attributions: [refused])
        XCTAssertEqual(items[0].attribution?.confidence, .refused)
    }
}
