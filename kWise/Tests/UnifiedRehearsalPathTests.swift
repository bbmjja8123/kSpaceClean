// kWise/Tests/UnifiedRehearsalPathTests.swift
//
// P2 T5 — 统一预演句式（R-统一，废除 P1 两层信任裁定）：
// 三入口（组头 .rehearse / hero 快捷回收 / 下钻勾选）全部
// 预演 → 确认 → executeConfirmedCleanup，共用同一个 CleanupViewModel
// 预演链；Smart Care orchestrator 不再拥有任何绕过预演的直执行路径。
import XCTest
@testable import kWise

@MainActor
final class UnifiedRehearsalPathTests: XCTestCase {
    // MARK: - Fixtures

    private func makeVM() -> (CleanupViewModel, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("unified-rehearsal-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let vm = CleanupViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true), quota: nil))
        return (vm, root)
    }

    @discardableResult
    private func makeFile(in root: URL, named name: String) -> URL {
        let url = root.appendingPathComponent(name)
        try? Data("x".utf8).write(to: url)
        return url
    }

    /// 组头入口的载体：直接构造画布组（entries 携带 T2 的 `CleanupTarget`）。
    private func makeGroup(kind: GroupKind,
                           title: String,
                           entries: [CanvasEntry]) -> CanvasGroup {
        CanvasGroup(id: kind,
                    icon: "trash",
                    title: title,
                    subtitle: "",
                    totalBytes: entries.reduce(0) { $0 + $1.bytes },
                    entries: entries,
                    action: .rehearse)
    }

    // MARK: - 入口 1：组头 .rehearse —— 只含该组 entries 的 targets

    func testGroupButtonRehearsalFilteredToGroupEntries() async {
        let (vm, root) = makeVM()
        let a1 = makeFile(in: root, named: "groupA-1.bin")
        let a2 = makeFile(in: root, named: "groupA-2.bin")
        let b1 = makeFile(in: root, named: "groupB-1.bin")

        let groupA = makeGroup(kind: .cause(.cache), title: "应用缓存", entries: [
            CanvasEntry(title: "a1", bytes: 1, badge: .recyclable,
                        target: CleanupTarget(url: a1, size: 1, risk: .recommended)),
            CanvasEntry(title: "a2", bytes: 2, badge: .recyclable,
                        target: CleanupTarget(url: a2, size: 2, risk: .recommended)),
        ])
        let groupB = makeGroup(kind: .duplicates, title: "重复文件", entries: [
            CanvasEntry(title: "b1", bytes: 4, badge: .recyclable,
                        target: CleanupTarget(url: b1, size: 4, risk: .recommended)),
        ])

        // 组头按钮的映射（与 RootView onGroupAction 同一表达式）。
        let items = await vm.makeRehearsal(targets: groupA.entries.compactMap(\.target))

        XCTAssertEqual(items.map(\.target.url), [a1, a2],
                       "组头预演与组 entries 1:1 同序 —— 其它组的条目绝不混入")
        XCTAssertEqual(vm.pendingTargets.map(\.url), [a1, a2],
                       "暂存集同样只含该组的 targets（确认只执行预演过的清单）")

        // 确认执行后：组 A 清掉，未预演的组 B 原样保留。
        await vm.executeConfirmedCleanup(confirmedTargets: items.map(\.target))
        XCTAssertFalse(FileManager.default.fileExists(atPath: a1.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: a2.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b1.path),
                      "未预演的组绝不因别组的预演被执行")
    }

    // MARK: - 入口 2：hero 快捷回收 —— 推荐项已勾选集（C4：无 dangerous）

    func testQuickCleanRehearsalUsesRecommendedPicks() async {
        let (vm, root) = makeVM()
        let safe = makeFile(in: root, named: "safe-cache.bin")
        let risky = makeFile(in: root, named: "dangerous-prefs.bin")

        let category = ScanCategory(categoryID: "c", title: "c", subItems: [
            ScanSubCategory(subCategoryID: "s", title: "s", actions: [ScanAction(
                actionID: "a", actionType: .cache, title: "a", results: [
                    ScanResult(url: safe, path: safe.path, title: "safe",
                               fileSize: 1, cleanType: .cache, riskLevel: .recommended),
                    ScanResult(url: risky, path: risky.path, title: "risky",
                               fileSize: 2, cleanType: .preference, riskLevel: .dangerous),
                ])])])
        let scanVM = ScanResultsViewModel(engine: nil)
        scanVM.assign(snapshot: .init(hasScanned: true, categories: [category]))
        let orch = SmartCareOrchestrator(scanResultsViewModel: scanVM)

        orch.start()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard case .confirming = orch.state else {
            return XCTFail("expected .confirming, got \(orch.state)")
        }

        // hero 快捷回收的预演入参（与 RootView presentQuickCleanRehearsal
        // 同一表达式）。
        let items = await vm.makeRehearsal(targets: orch.recommendedTargets)

        XCTAssertEqual(items.map(\.target.url), [safe],
                       "快捷回收预演 = 推荐项已勾选集；危险项绝不进入（C4 红线）")
        XCTAssertTrue(items.allSatisfy { $0.target.risk == .recommended })

        // 确认执行：只有推荐项被清理，dangerous 文件原样保留。
        await vm.executeConfirmedCleanup(confirmedTargets: items.map(\.target))
        XCTAssertFalse(FileManager.default.fileExists(atPath: safe.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: risky.path),
                      "危险文件绝不能经快捷回收被删除（C4）")
    }

    // MARK: - 入口 3：下钻勾选 —— 选中集（T6 下钻页消费的 VM 级契约）

    func testDrillDownRehearsalMirrorsCheckedLeaves() async {
        let (vm, root) = makeVM()
        let f1 = makeFile(in: root, named: "checked-1.bin")
        let f2 = makeFile(in: root, named: "unchecked.bin")
        let f3 = makeFile(in: root, named: "checked-3.bin")

        // 下钻页的勾选集：f1 / f3 勾选，f2 未勾选 —— 预演只镜像勾选叶。
        let checked: [CleanupTarget] = [f1, f3].map {
            CleanupTarget(url: $0, size: 1, risk: .recommended)
        }
        let items = await vm.makeRehearsal(targets: checked)

        XCTAssertEqual(items.map(\.target.url), [f1, f3],
                       "预演与勾选集 1:1 同序（未勾选的 f2 绝不出现）")

        // sheet 上再取消勾选 f3 —— 确认集只含 f1，执行也只清 f1。
        let confirmed = items.filter { $0.target.url != f3 }.map(\.target)
        await vm.executeConfirmedCleanup(confirmedTargets: confirmed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f2.path), "未勾选叶保留")
        XCTAssertTrue(FileManager.default.fileExists(atPath: f3.path), "sheet 上豁免的行保留")
    }

    // MARK: - fix r1（Important 2）：失败运行不得继承上次成功的 outcome

    /// 成功一次 → 注入系统性失败（确认集里的文件在 sheet → confirm 之间
    /// 消失，真实竞态）→ 本次运行的返回值与 `lastOutcome` 必须反映失败
    ///（freed 0），绝不能把上次成功的字节顶给 doneHero。
    func testFailedRunNeverInheritsPreviousSuccessOutcome() async {
        let (vm, root) = makeVM()
        let f1 = makeFile(in: root, named: "run1-a.bin")
        let f2 = makeFile(in: root, named: "run1-b.bin")

        // 第一次运行：真实成功，freedBytes = 1 + 2。
        let items = await vm.makeRehearsal(sizes: [f1: 1, f2: 2], urls: [f1, f2])
        let first = await vm.executeConfirmedCleanup(confirmedTargets: items.map(\.target))
        XCTAssertEqual(first?.freedBytes, 3)
        XCTAssertEqual(vm.lastOutcome?.freedBytes, 3)

        // 第二次运行（失败注入）： vanished 路径绕过预演存在性过滤 ——
        // 与「sheet 打开期间文件被删」的真实竞态同构。
        let vanished = CleanupTarget(url: root.appendingPathComponent("vanished.bin"),
                                     size: 9)
        let outcome = await vm.executeConfirmedCleanup(confirmedTargets: [vanished])
        XCTAssertEqual(outcome?.succeeded.isEmpty, true, "失败运行不得有成功项")
        XCTAssertEqual(outcome?.freedBytes, 0)
        XCTAssertEqual(outcome?.failed.count, 1)
        XCTAssertEqual(vm.lastOutcome?.freedBytes, 0,
                       "lastOutcome 必须反映本次失败运行（进场即清旧值）")
        XCTAssertEqual(vm.lastOutcome?.failed.count, 1)
        XCTAssertEqual(vm.lastResult?.snapshots.isEmpty, true,
                       "lastResult 同样不得残留上次成功的快照")
    }

    // MARK: - 两层信任豁免废除：orchestrator 不再直执行

    /// 旧 `confirm()` 在 `.confirming` 一键直执行引擎 —— 已废除。现在
    /// `.confirming` 停在那里等预演 sheet；执行结果由宿主经预演链跑完后
    /// 回填（beginExecution → completeExecution / failExecution）。
    func testOrchestratorStaysInConfirmingUntilHostCompletesExecution() async {
        let (vm, root) = makeVM()
        let safe = makeFile(in: root, named: "safe-cache.bin")
        let category = ScanCategory(categoryID: "c", title: "c", subItems: [
            ScanSubCategory(subCategoryID: "s", title: "s", actions: [ScanAction(
                actionID: "a", actionType: .cache, title: "a", results: [
                    ScanResult(url: safe, path: safe.path, title: "safe",
                               fileSize: 1, cleanType: .cache, riskLevel: .recommended),
                ])])])
        let scanVM = ScanResultsViewModel(engine: nil)
        scanVM.assign(snapshot: .init(hasScanned: true, categories: [category]))
        let orch = SmartCareOrchestrator(scanResultsViewModel: scanVM)

        orch.start()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard case .confirming = orch.state else {
            return XCTFail("expected .confirming, got \(orch.state)")
        }

        // orchestrator 自己绝不执行 —— 不经预演链文件必须原样保留。
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: safe.path),
                      "两层信任豁免废除：.confirming 不得绕过预演直执行")
        if case .confirming = orch.state {} else {
            XCTFail("确认态保持等待预演 sheet，got \(orch.state)")
        }

        // 宿主回填路径：预演 sheet 确认 → 统一链执行 → 结果回填。
        orch.beginExecution()
        XCTAssertEqual(orch.state, .cleaning(progress: 0))
        orch.completeExecution(freedBytes: 42, durationSeconds: 0.1)
        if case .done(let freed, _) = orch.state {
            XCTAssertEqual(freed, 42, "doneHero 展示统一链回填的真实释放字节")
        } else {
            XCTFail("expected .done, got \(orch.state)")
        }

        orch.failExecution(message: "清理未能完成")
        if case .failed = orch.state {} else {
            XCTFail("expected .failed, got \(orch.state)")
        }
    }
}
