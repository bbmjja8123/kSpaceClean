// kWise/Tests/CleanupViewModelRehearsalTests.swift
//
// P1 T4 — CleanupViewModel 两段式（预演 → 确认执行）契约测试。
// 红线：预演 == 执行（1:1 同序）、空 pendingTargets 绝不兜底执行上次清单。
import XCTest
@testable import kWise

@MainActor
final class CleanupViewModelRehearsalTests: XCTestCase {
    private func makeVM(attributions: [SpaceAttribution]) -> (CleanupViewModel, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rehearsal-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let vm = CleanupViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true), quota: nil))
        vm.attributionLookup = { attributions }
        return (vm, root)
    }

    func testRehearsalMirrorsSelectedURLsOneToOne() async {
        let (vm, root) = makeVM(attributions: [])
        let a = root.appendingPathComponent("a.bin"); let b = root.appendingPathComponent("b.bin")
        try? Data("x".utf8).write(to: a); try? Data("y".utf8).write(to: b)

        let items = await vm.makeRehearsal(sizes: [a: 1, b: 2],
                                           urls: [a, b])
        XCTAssertEqual(items.map(\.target.url), [a, b], "预演 == 执行（1:1 同序）")
        XCTAssertEqual(vm.pendingTargets.count, 2)
    }

    func testExecuteUsesPendingTargetsExactly() async {
        let (vm, root) = makeVM(attributions: [])
        let a = root.appendingPathComponent("a.bin")
        try? Data("x".utf8).write(to: a)
        _ = await vm.makeRehearsal(sizes: [a: 1], urls: [a])

        await vm.executeConfirmedCleanup(sizes: [a: 1])
        XCTAssertTrue(vm.lastOutcome?.succeeded.isEmpty == false,
                      "确认后执行必须真正清理 pendingTargets")
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
    }

    /// 红线自审项：空 pendingTargets 时 execute 必须是 no-op ——
    /// 绝不把「上次预演的 targets」当成兜底执行。
    func testExecuteWithEmptyPendingTargetsIsNoOp() async {
        let (vm, root) = makeVM(attributions: [])
        let a = root.appendingPathComponent("a.bin")
        try? Data("x".utf8).write(to: a)

        await vm.executeConfirmedCleanup(sizes: nil)
        XCTAssertTrue(vm.lastOutcome == nil, "空 pendingTargets 不产生任何 outcome")
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path), "文件原样保留")
    }

    /// 预演项必须带归因（来自 attributionLookup），缺席时诚实为 nil。
    func testRehearsalCarriesAttributionFromLookup() async {
        let (vm, root) = makeVM(attributions: [])
        let a = root.appendingPathComponent("a.bin")
        try? Data("x".utf8).write(to: a)

        // CleanRehearsal.build 按路径首段匹配 —— 这里让归因覆盖该路径。
        let covering = SpaceAttribution(
            scope: .fileTree, paths: [a.path], bytes: 1, owner: .system, cause: .cache,
            reclaim: .recycles(expectedDays: 3), confidence: .certain,
            source: .rule, ruleID: "caches.app-generic", evidence: [], lastModified: nil)
        vm.attributionLookup = { [covering] }

        let items = await vm.makeRehearsal(sizes: [a: 1], urls: [a])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].attribution?.ruleID, "caches.app-generic")
        XCTAssertEqual(items[0].target.size, 1, "预演 target 的大小来自 sizes 入参")
    }

    // MARK: - r1 review fixes

    /// r1 Critical 1 —— 排除侧契约：sheet 上取消勾选的行**绝不执行**。
    /// 预演 2 项，确认只传 a 的 target（模拟 sheet 的 exempt 交互）→
    /// b 必须原样保留。
    func testConfirmCarriesOnlyConfirmedSubset() async {
        let (vm, root) = makeVM(attributions: [])
        let a = root.appendingPathComponent("a.bin")
        let b = root.appendingPathComponent("b.bin")
        try? Data("x".utf8).write(to: a)
        try? Data("y".utf8).write(to: b)

        let items = await vm.makeRehearsal(sizes: [a: 1, b: 2], urls: [a, b])
        XCTAssertEqual(items.count, 2)
        // 用户在 CleanupRehearsalSheet 里取消勾选 b —— onConfirm 只带 a。
        let confirmed = items.filter { $0.target.url != b }.map(\.target)
        XCTAssertEqual(confirmed.count, 1)

        await vm.executeConfirmedCleanup(sizes: nil, confirmedTargets: confirmed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path), "勾选项被清理")
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path),
                      "取消勾选的行绝不能被删除（r1 Critical 1）")
        XCTAssertTrue(vm.pendingTargets.isEmpty, "执行后暂存作废，不可重放")
    }

    /// r1 Important 2 —— notes 行必须本地化解析，而不是渲染裸 key。
    /// 插值写法会查 `attr.notes.%@`（不存在）→ 返回裸 key；拼接写法查
    /// `attr.notes.<ruleID>`（xcstrings 在）。测试宿主语言环境不可控，
    /// 故断言「≠ 裸 key 字符串」且不带 key 前缀（coordinator 裁定形式）。
    func testNotesLineResolvesLocalizedNotBareKey() {
        let resolved = String(localized: String.LocalizationValue(
            "attr.notes." + "caches.app-generic"))
        XCTAssertNotEqual(resolved, "attr.notes.caches.app-generic",
                          "拼接 key 必须命中 xcstrings 译文，而非渲染裸 key")
        XCTAssertFalse(resolved.hasPrefix("attr.notes."),
                       "解析结果不得带 key 前缀（裸 key 查表失配的特征）")
        XCTAssertFalse(resolved.isEmpty)
    }

    /// r1 Important 3 —— 双击/重放守卫：执行后暂存已清空，第二次调用
    /// 是 no-op（不产生新 outcome、不改变上次结果）。
    func testSecondExecuteAfterRunIsNoOp() async {
        let (vm, root) = makeVM(attributions: [])
        let a = root.appendingPathComponent("a.bin")
        try? Data("x".utf8).write(to: a)
        _ = await vm.makeRehearsal(sizes: [a: 1], urls: [a])

        await vm.executeConfirmedCleanup(sizes: nil)
        let firstSucceeded = vm.lastOutcome?.succeeded ?? []
        XCTAssertEqual(firstSucceeded, [a])

        // 第二次（重复点击/重放）：pendingTargets 已在首次进入时清空。
        await vm.executeConfirmedCleanup(sizes: nil)
        XCTAssertEqual(vm.lastOutcome?.succeeded ?? [], firstSucceeded,
                       "第二次执行必须是 no-op，结果不变")
        XCTAssertTrue(vm.pendingTargets.isEmpty)
    }

    /// P1 final (F3a) —— RootView 的 lookup 供 `report.allAttributions`
    /// （certain + refused/probable 全量）。旧实现只供 `report.items`：
    /// probable 分支哑火、refused 项显示成「无归因信息」。本测试钉：
    /// probable 归因必须随 lookup 到达预演项。
    func testRehearsalCarriesProbableFromFullReportLookup() async {
        let (vm, root) = makeVM(attributions: [])
        let certainURL = root.appendingPathComponent("c.bin")
        let probableURL = root.appendingPathComponent("p.bin")
        try? Data("x".utf8).write(to: certainURL)
        try? Data("y".utf8).write(to: probableURL)

        let certain = SpaceAttribution(
            scope: .fileTree, paths: [certainURL.path], bytes: 1, owner: .system,
            cause: .cache, reclaim: .recycles(expectedDays: 3), confidence: .certain,
            source: .rule, ruleID: "caches.app-generic", evidence: [], lastModified: nil)
        let probable = SpaceAttribution(
            scope: .fileTree, paths: [probableURL.path], bytes: 1, owner: .unknown,
            cause: .unknown, reclaim: .uncertain, confidence: .probable,
            source: .nlEmbedding, ruleID: nil, evidence: [], lastModified: nil)
        let report = AttributionReport(
            items: [certain], refused: [probable], unattributedBytes: 0,
            blackBox: BlackBoxBreakdown(usedBytes: 2, visibleBytes: 2,
                                        residualBytes: 0, snapshotCount: 1,
                                        status: .reconciled),
            snapshots: nil, generatedAt: Date())
        XCTAssertEqual(report.allAttributions.count, 2,
                       "allAttributions = items + refused（F3a 扩面的载体）")
        vm.attributionLookup = { report.allAttributions }

        let items = await vm.makeRehearsal(sizes: [certainURL: 1, probableURL: 1],
                                           urls: [certainURL, probableURL])
        XCTAssertEqual(items.first { $0.target.url == certainURL }?.attribution?.ruleID,
                       "caches.app-generic")
        XCTAssertEqual(items.first { $0.target.url == probableURL }?.attribution?.confidence,
                       .probable, "probable 归因必须到达预演（旧 lookup 只供 items，此分支哑火）")
    }
}
