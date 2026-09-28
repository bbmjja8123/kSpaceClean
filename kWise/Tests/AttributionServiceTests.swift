import XCTest
@testable import kWise

final class AttributionServiceTests: XCTestCase {
    private let home = "/Users/tester"

    private func rule(_ id: String, _ glob: String, owner: AttributionOwnerSpec,
                      cause: AttributionCause, reclaim: Reclaimability) -> AttributionRule {
        AttributionRule(id: id, match: AttributionRuleMatch(pathGlob: glob), owner: owner,
                        cause: cause, reclaim: reclaim, notesKey: "attr.notes.\(id)")
    }

    private func result(_ path: String, bytes: Int64) -> ScanResult {
        ScanResult(url: URL(fileURLWithPath: path), path: path, title: "x",
                   fileSize: bytes, cleanType: .cache)
    }

    /// category → sub → action → results 的最小树（与生产形状一致）。
    private func category(results: [ScanResult]) -> [ScanCategory] {
        let action = ScanAction(actionID: "a", actionType: .cache, title: "a",
                                totalSize: results.reduce(0) { $0 + $1.fileSize },
                                results: results)
        let sub = ScanSubCategory(subCategoryID: "s", title: "s",
                                  totalSize: action.totalSize, actions: [action])
        return [ScanCategory(categoryID: "c", title: "c",
                             totalSize: sub.totalSize, subItems: [sub])]
    }

    private struct StubRunner: VolumeCommandRunning {
        let status: Int32
        func run(arguments: [String]) async -> (status: Int32, stdout: String) {
            (status, status == 0 ? "<plist version=\"1.0\"><array/></plist>" : "")
        }
    }

    private func makeService(rules: [AttributionRule],
                             used: Int64?,
                             snapshotStatus: Int32 = 0) -> AttributionService {
        AttributionService(
            engine: AttributionRuleEngine(corpus: AttributionRuleCorpus(schemaVersion: 1, rules: rules),
                                          homeDirectory: home),
            volumeReader: VolumeLayerReader(runner: StubRunner(status: snapshotStatus)),
            volumeUsedBytesProvider: { used })
    }

    func testRoutingItemsRefusedAndUnattributed() async {
        let service = makeService(rules: [
            rule("xcode.derived-data", "~/Library/Developer/Xcode/DerivedData/**",
                 owner: .app(bundleID: "com.apple.dt.Xcode", appName: "Xcode"),
                 cause: .developerCache, reclaim: .recycles(expectedDays: 30)),
            rule("wechat.files", "~/Library/Containers/com.tencent.xinWeChat/**",
                 owner: .app(bundleID: "com.tencent.xinWeChat", appName: "微信"),
                 cause: .chatFiles, reclaim: .uncertain),
        ], used: 10_000)
        let report = await service.attribute(categories: category(results: [
            result("/Users/tester/Library/Developer/Xcode/DerivedData/x", bytes: 300),   // → items
            result("/Users/tester/Library/Containers/com.tencent.xinWeChat/f", bytes: 200), // → refused
            result("/Users/tester/mystery-huge.bin", bytes: 500_000_000),                // → refused（≥阈值）
            result("/Users/tester/small-orphan.bin", bytes: 10),                         // → unattributedBytes
        ]))
        XCTAssertEqual(report.items.count, 1)
        XCTAssertEqual(report.items.first?.ruleID, "xcode.derived-data")
        XCTAssertEqual(report.refused.count, 2)
        XCTAssertTrue(report.refused.allSatisfy { $0.reclaim == .uncertain })
        XCTAssertEqual(report.unattributedBytes, 10)
    }

    func testBlackBoxReconcilesWithVisibleSum() async {
        let service = makeService(rules: [], used: 1_000)
        let report = await service.attribute(categories: category(results: [
            result("/Users/tester/a", bytes: 300),
            result("/Users/tester/b", bytes: 200),
        ]))
        XCTAssertEqual(report.blackBox.visibleBytes, 500)
        XCTAssertEqual(report.blackBox.residualBytes, 500)
        XCTAssertEqual(report.blackBox.status, .reconciled)
    }

    func testSnapshotCountFlowsIntoBlackBox() async {
        let service = makeService(rules: [], used: 1_000)
        let report = await service.attribute(categories: category(results: []))
        XCTAssertEqual(report.blackBox.snapshotCount, 0, "空数组 = 无快照，合法")
        XCTAssertNotNil(report.snapshots)
    }

    func testUnreadableVolumeLeavesSnapshotsNil() async {
        let service = makeService(rules: [], used: 1_000, snapshotStatus: 1)
        let report = await service.attribute(categories: category(results: []))
        XCTAssertNil(report.snapshots, "读取失败必须显式为 nil，禁止 [] 冒充")
    }

    func testFlattenWalksWholeTree() async {
        let deep = result("/Users/tester/deep", bytes: 5)
        let action = ScanAction(actionID: "a", actionType: .cache, title: "a",
                                results: [result("/Users/tester/shallow", bytes: 3)])
        // NOTE: 实参顺序按 ScanSubCategory 声明序排列（Swift 不允许乱序标签）；
        // 语义不变 —— showAction == true 时 actions 与 directResults 并存。
        let sub = ScanSubCategory(subCategoryID: "s", title: "s",
                                  actions: [action], directResults: [deep], showAction: true)
        let service = makeService(rules: [], used: nil)
        let report = await service.attribute(categories: [
            ScanCategory(categoryID: "c", title: "c", subItems: [sub])
        ])
        XCTAssertEqual(report.blackBox.visibleBytes, 8, "action.results 与 directResults 都要走到")
    }

    // MARK: live() 装配（final review C1）

    /// C1 根因回归：live() 曾把 `NSHomeDirectory()`（沙箱容器路径）喂给引擎，
    /// 而扫描结果携带真实家目录路径 —— 所有 `~/Library/...` 语料 glob 永不命中，
    /// 生产语料整体沦为死规则。此处钉住：注入的 home 必须一路接进引擎的 glob 展开，
    /// 使真实家目录形态的扫描路径能命中语料规则。
    func testLiveWiresHomeIntoEngine() {
        let service = AttributionService.live(home: "/Users/x")
        XCTAssertEqual(service.engine.homeDirectory, "/Users/x",
                       "live(home:) 必须把 home 原样接入引擎（不得回落到 NSHomeDirectory）")

        XCTAssertFalse(service.engine.corpus.rules.isEmpty,
                       "attribution_rules.json 必须打进 App bundle，live() 不得空语料降级")

        // 端到端：真实家目录形态的路径（/Users/x/Library/Caches/...）经 live 语料的
        // caches.app-generic（~/Library/Caches/**）命中 —— home 接错时必不命中。
        let hit = service.engine.attribute(results: [
            result("/Users/x/Library/Caches/SomeApp/cache.bin", bytes: 4096),
        ])
        XCTAssertEqual(hit.first?.ruleID, "caches.app-generic",
                       "真实家目录路径必须能命中语料的 caches 通配规则")
    }
}
