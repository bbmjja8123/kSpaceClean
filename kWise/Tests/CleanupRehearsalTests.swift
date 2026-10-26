import XCTest
@testable import kWise

@MainActor
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

    // MARK: - I1（P2 final）：徽章进预演 + 非绿徽默认豁免（C4）

    /// 含「数据·不属垃圾」条目的组预演 → 该项初始豁免（锁定测试）。
    func testDataNotJunkEntryDefaultsExempted() {
        let items = [
            RehearsalItem(target: target("/junk"), attribution: nil, badge: .recyclable),
            RehearsalItem(target: target("/data"), attribution: nil, badge: .dataNotJunk),
            RehearsalItem(target: target("/migrate"), attribution: nil, badge: .migrate),
            RehearsalItem(target: target("/attention"), attribution: nil, badge: .attention),
            RehearsalItem(target: target("/leave"), attribution: nil, badge: .leaveAlone),
            // 无徽章（快捷回收推荐项等树来源）→ 保持默认勾选。
            RehearsalItem(target: target("/tree-pick"), attribution: nil, badge: nil),
        ]
        let exempted = CleanupRehearsal.defaultExemptedPaths(for: items)
        XCTAssertEqual(exempted, ["/data", "/migrate", "/attention", "/leave"],
                       "非 .recyclable 徽章一律初始豁免（C4）；绿徽与无徽章默认勾选")
    }

    /// `makeRehearsal(entries:)` 把 CanvasEntry 的徽章原样带进预演项。
    func testMakeRehearsalEntriesCarriesBadge() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rehearsal-badge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let junk = root.appendingPathComponent("junk.bin")
        let data = root.appendingPathComponent("data.bin")
        try Data("x".utf8).write(to: junk)
        try Data("x".utf8).write(to: data)

        let vm = CleanupViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true), quota: nil))
        let entries = [
            CanvasEntry(title: "junk", bytes: 10, badge: .recyclable,
                        target: CleanupTarget(url: junk, size: 10, risk: .recommended)),
            CanvasEntry(title: "data", bytes: 20, badge: .dataNotJunk,
                        target: CleanupTarget(url: data, size: 20, risk: .optional)),
        ]
        let items = await vm.makeRehearsal(entries: entries)
        XCTAssertEqual(items.map(\.target.url), [junk, data], "与条目 1:1 同序")
        XCTAssertEqual(items.map(\.badge), [.recyclable, .dataNotJunk],
                       "徽章随条目进预演（sheet 据此渲染五色徽章列 + 默认豁免）")
        XCTAssertEqual(CleanupRehearsal.defaultExemptedPaths(for: items), [data.path],
                       "含 dataNotJunk 条目的组预演 → 该项初始 exempted")
    }

    /// Task 8 review Important 1：条目 detail 随 `makeRehearsal(entries:)`
    /// 进预演项 —— sheet 行在确认时刻渲染它（如 iOS 备份的删除语义）；
    /// 无 detail 的条目 detail 为 nil（退归因 reason 渲染，行为不变）。
    func testMakeRehearsalEntriesCarriesDetail() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rehearsal-detail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let backup = root.appendingPathComponent("DEV1")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        let plain = root.appendingPathComponent("plain.txt")
        try Data("x".utf8).write(to: plain)

        let vm = CleanupViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true), quota: nil))
        let warning = "仅本机备份的删除语义警告"
        let entries = [
            CanvasEntry(title: "DEV1", bytes: 10, badge: .attention, detail: warning,
                        target: CleanupTarget(url: backup, size: 10, risk: .caution)),
            CanvasEntry(title: "plain", bytes: 1, badge: .recyclable,
                        target: CleanupTarget(url: plain, size: 1, risk: .recommended)),
        ]
        let items = await vm.makeRehearsal(entries: entries)
        XCTAssertEqual(items.first?.detail, warning,
                       "带 detail 的条目在 sheet 行可见（确认时刻的删除语义）")
        XCTAssertNil(items.last?.detail, "无 detail 条目保持既有 reason 渲染路径")
    }
}
