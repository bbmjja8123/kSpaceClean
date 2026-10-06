// kWise/Tests/GroupDrillDownTests.swift
//
// P2 T6 — 分组下钻页（GroupDrillDownView）的 VM 级契约：
// - 默认勾选态按徽章（C4：绿 ✓ 可回收勾上，其余一律不勾）；
// - 勾选集 → 预演 targets 1:1（经 CleanupViewModel.makeRehearsal(targets:) 同一条链）；
// - 面包屑返回（视图销毁）后再进同一组，勾选态由 VM 缓存原样保留；
// - cause 组从扫描树按 cause 切片（AttributionService.flatten + 引擎映射），
//   detection 组直接用 CanvasEntry（T2 组装器全量）；
// - AssistantNodePanel 参数化（问题集可注入，DetailPanel 默认集不变）。
import XCTest
@testable import kWise

@MainActor
final class GroupDrillDownTests: XCTestCase {

    // MARK: - Fixtures

    private var nextID = 0

    private func entry(title: String,
                       bytes: Int64,
                       badge: BadgeKind,
                       path: String? = nil) -> CanvasEntry {
        nextID += 1
        return CanvasEntry(
            title: title,
            bytes: bytes,
            badge: badge,
            detail: path,
            target: path.map {
                CleanupTarget(url: URL(fileURLWithPath: $0),
                              size: bytes,
                              risk: badge == .leaveAlone ? .dangerous : .recommended)
            })
    }

    /// 混合徽章的组：1 绿 / 1 蓝 / 1 红 / 1 灰（默认勾选态必须只勾绿）。
    private func mixedEntries() -> [CanvasEntry] {
        [
            entry(title: "cache.bin", bytes: 100, badge: .recyclable,
                  path: "/tmp/dd/cache.bin"),
            entry(title: "big.mov", bytes: 900, badge: .migrate,
                  path: "/tmp/dd/big.mov"),
            entry(title: "photos.db", bytes: 300, badge: .dataNotJunk,
                  path: "/tmp/dd/photos.db"),
            entry(title: "unknown.dir", bytes: 50, badge: .leaveAlone,
                  path: "/tmp/dd/unknown.dir"),
        ]
    }

    private func group(entries: [CanvasEntry],
                       kind: GroupKind = .cause(.cache)) -> CanvasGroup {
        CanvasGroup(id: kind, icon: "trash", title: "测试组",
                    subtitle: "", totalBytes: entries.reduce(0) { $0 + $1.bytes },
                    entries: entries, action: .rehearse)
    }

    private func makeAnatomyViewModel() -> AnatomyViewModel {
        AnatomyViewModel(service: AttributionService(
            engine: AttributionRuleEngine(
                corpus: AttributionRuleCorpus(schemaVersion: 1, rules: []),
                homeDirectory: "/Users/tester"),
            volumeReader: nil,
            volumeUsedBytesProvider: { nil }))
    }

    // MARK: - 默认勾选态（C4）

    func testDefaultCheckedStateFollowsBadge() {
        let entries = mixedEntries()
        let model = GroupDrillDownModel(group: group(entries: entries), entries: entries)

        XCTAssertTrue(model.isChecked(entries[0].id), "绿 ✓ 可回收默认勾选")
        XCTAssertFalse(model.isChecked(entries[1].id), "蓝 迁出默认不勾")
        XCTAssertFalse(model.isChecked(entries[2].id), "红 数据·不属垃圾默认不勾")
        XCTAssertFalse(model.isChecked(entries[3].id), "灰 不动·不敢判默认不勾")
    }

    func testTogglingFlipsCheckedState() {
        let entries = mixedEntries()
        let model = GroupDrillDownModel(group: group(entries: entries), entries: entries)

        model.toggle(entries[2].id)
        XCTAssertTrue(model.isChecked(entries[2].id))
        model.toggle(entries[2].id)
        XCTAssertFalse(model.isChecked(entries[2].id))
        model.setChecked(entries[0].id, false)
        XCTAssertFalse(model.isChecked(entries[0].id), "可回收项也可手动取消")
    }

    /// 勾选字节只计带 target 的条目 —— 无 target 的勾选项既不预演也不夸大。
    func testCheckedBytesCountsOnlyTargetBearingEntries() {
        let targetless = CanvasEntry(title: "no-target", bytes: 777, badge: .recyclable)
        var entries = mixedEntries()
        entries.append(targetless)
        let model = GroupDrillDownModel(group: group(entries: entries), entries: entries)

        XCTAssertEqual(model.checkedBytes, 100,
                       "默认勾选 = 唯一绿徽（带 target）→ 100 字节；无 target 的 777 不计")
    }

    // MARK: - 勾选集 → 预演 targets 1:1

    func testCheckedTargetsMirrorCheckedEntriesInOrder() {
        let entries = mixedEntries()
        let model = GroupDrillDownModel(group: group(entries: entries), entries: entries)

        model.toggle(entries[1].id) // 蓝 迁出加入勾选
        model.toggle(entries[3].id) // 灰（dangerous）用户显式勾选 —— 明示意图入预演
        model.toggle(entries[0].id) // 绿取消

        let targets = model.checkedTargets
        XCTAssertEqual(targets.map(\.id),
                       [entries[1].target?.id, entries[3].target?.id].compactMap { $0 },
                       "勾选集 → targets 1:1、保持 entries 顺序，未勾/已取消的不进；"
                           + "C4 只约束默认态 —— 显式勾选的 dangerous 项如实进预演（"
                           + "risk 元数据原样携带，由预演 sheet 呈现风险）")
    }

    func testCheckedSetRehearsesOneToOneThroughUnifiedChain() async {
        // 真实临时文件 —— makeRehearsal 的存在性过滤需要路径可达。
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("drilldown-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let names = ["cache.bin", "big.mov", "photos.db", "unknown.dir"]
        var entries = mixedEntries()
        for (index, name) in names.enumerated() {
            let url = root.appendingPathComponent(name)
            try? Data("x".utf8).write(to: url)
            let old = entries[index]
            entries[index] = CanvasEntry(
                id: old.id, title: old.title, bytes: old.bytes, badge: old.badge,
                detail: old.detail,
                target: CleanupTarget(id: old.target?.id ?? UUID(),
                                      url: url, size: old.bytes,
                                      risk: old.target?.risk ?? .recommended))
        }
        let model = GroupDrillDownModel(group: group(entries: entries), entries: entries)
        model.toggle(entries[2].id) // 红 徽手动加入 —— 用户明示意图，允许进预演

        let vm = CleanupViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true), quota: nil))
        vm.attributionLookup = { [] }
        let items = await vm.makeRehearsal(targets: model.checkedTargets)

        XCTAssertEqual(items.map(\.target.id), model.checkedTargets.map(\.id),
                       "预演 == 勾选集（1:1 同序，T6 下钻消费 T5 的 target 直入链）")
    }

    // MARK: - 面包屑返回保持勾选（VM 级）

    func testBreadcrumbBackPreservesCheckedStateInVMCache() {
        let viewModel = makeAnatomyViewModel()
        let entries = mixedEntries()
        let drillGroup = group(entries: entries)

        let first = viewModel.drillDownModel(for: drillGroup, entries: entries)
        first.toggle(entries[2].id)
        first.setChecked(entries[0].id, false)

        // 面包屑返回 = 下钻视图销毁；再次进入同一组必须取回同一份 VM。
        let reopened = viewModel.drillDownModel(for: drillGroup, entries: entries)
        XCTAssertTrue(reopened === first, "同组再进必须复用同一 VM（勾选态不丢）")
        XCTAssertTrue(reopened.isChecked(entries[2].id), "手动勾上的保留")
        XCTAssertFalse(reopened.isChecked(entries[0].id), "手动取消的保留")
    }

    func testDrillDownCacheIsPerGroup() {
        let viewModel = makeAnatomyViewModel()
        let a = viewModel.drillDownModel(for: group(entries: mixedEntries(), kind: .cause(.cache)),
                                         entries: mixedEntries())
        let b = viewModel.drillDownModel(for: group(entries: mixedEntries(), kind: .duplicates),
                                         entries: mixedEntries())
        XCTAssertFalse(a === b, "不同组各持一份勾选态")
    }

    // MARK: - 数据切片（spec §6）

    private func corpus(_ rules: [AttributionRule]) -> AttributionRuleCorpus {
        AttributionRuleCorpus(schemaVersion: 1, rules: rules)
    }

    private func rule(_ id: String, _ glob: String,
                      cause: AttributionCause, reclaim: Reclaimability) -> AttributionRule {
        AttributionRule(id: id,
                        match: AttributionRuleMatch(pathGlob: glob),
                        owner: .app(bundleID: "com.example.app", appName: "Example"),
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

    func testCauseGroupSlicesTreeByCause() {
        let engine = AttributionRuleEngine(corpus: corpus([
            rule("xcode.derived-data", "~/Library/Developer/Xcode/DerivedData/**",
                 cause: .developerCache, reclaim: .recycles(expectedDays: 30)),
            rule("user.caches", "~/Library/Caches/**",
                 cause: .cache, reclaim: .recycles(expectedDays: 7)),
        ]), homeDirectory: "/Users/tester")

        let devPath = "/Users/tester/Library/Developer/Xcode/DerivedData/App/build"
        let cachePath = "/Users/tester/Library/Caches/App/scratch"
        let tree = category(results: [result(devPath, bytes: 4096),
                                      result(cachePath, bytes: 2048)])

        let devGroup = CanvasGroup(id: .cause(.developerCache), icon: "hammer",
                                   title: "开发缓存", subtitle: "", totalBytes: 4096,
                                   entries: [], action: .rehearse)
        let entries = GroupDrillDownSource.entries(for: devGroup, categories: tree, engine: engine)

        XCTAssertEqual(entries.count, 1, "cause 切片只含该 cause 的树条目")
        XCTAssertEqual(entries.first?.title, "build")
        XCTAssertEqual(entries.first?.detail, devPath)
        XCTAssertEqual(entries.first?.target?.url, URL(fileURLWithPath: devPath))
        XCTAssertEqual(entries.first?.badge, .recyclable)
        XCTAssertEqual(entries.first?.bytes, 4096)
    }

    func testDetectionGroupUsesCanvasEntriesDirectly() {
        let engine = AttributionRuleEngine(corpus: corpus([]), homeDirectory: "/Users/tester")
        let entries = mixedEntries()
        let dupGroup = group(entries: entries, kind: .duplicates)

        XCTAssertEqual(GroupDrillDownSource.entries(for: dupGroup, categories: [], engine: engine),
                       entries,
                       "detection 组直接用 CanvasEntry（T2 组装器全量），不经树切片")
    }

    /// 引擎切片为空（语料缺失/树已清）时回退组内全量条目 —— 与组卡同源，不是伪造。
    func testCauseSliceFallsBackToGroupEntriesWhenEngineYieldsNothing() {
        let engine = AttributionRuleEngine(corpus: corpus([]), homeDirectory: "/Users/tester")
        let entries = mixedEntries()
        let causeGroup = group(entries: entries, kind: .cause(.cache))

        XCTAssertEqual(GroupDrillDownSource.entries(for: causeGroup, categories: [], engine: engine),
                       entries)
    }

    // MARK: - AssistantNodePanel 参数化（T6 复用化）

    func testNodePanelQuestionsParameterized() {
        let custom = ["磁盘什么时候会满？"]
        let model = AssistantNodePanelModel(scanResultsProvider: { nil }, questions: custom)
        XCTAssertEqual(model.questions, custom, "下钻页可注入自己的建议问题集")
        XCTAssertEqual(AssistantNodePanelModel(scanResultsProvider: { nil }).questions,
                       AssistantNodePanelModel.suggestedQuestions,
                       "DetailPanel 默认问题集不变（复用化回归面）")
    }
}
