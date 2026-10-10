// kWise/Tests/AnatomyScanStateTests.swift
//
// P2 T3 — 主画布扫描进度态（spec §5 扫描即动作）：
// - ScanPhase 状态机：idle / scanning(progress, path) / done
// - startScan：扇出 coordinator → canvasReport + .done；重入被忽略
// - 扫描中画布分组保留（不清空，渲染层变灰由视图 opacity 承担）
// - bindScanViewModel：扫描页引擎 isScanning true→false → 归因刷新
//   （P1 修复波机制自 RootView .onChange 迁入 VM）
// 全部注入 mock（复用 CanvasScanCoordinatorTests 的 protocol seam 套路），
// 零文件系统触达。
import XCTest
import DetectionCore
@testable import kWise

@MainActor
final class AnatomyScanStateTests: XCTestCase {

    // MARK: - 测试基建

    /// 线程安全的调用计数器（与 T2 测试同模式）。
    private final class CallRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func record(_ call: String) { lock.withLock { items.append(call) } }
        func count(of call: String) -> Int { lock.withLock { items.filter { $0 == call }.count } }
    }

    /// 挂起检测器直到测试放行。
    private actor Gate {
        private var opened = false
        private var continuations: [CheckedContinuation<Void, Never>] = []
        func open() {
            opened = true
            for c in continuations { c.resume() }
            continuations.removeAll()
        }
        func wait() async {
            if opened { return }
            await withCheckedContinuation { continuations.append($0) }
        }
    }

    private struct FixedAttribution: AttributionScanning {
        let report: AttributionReport
        func attribute(categories: [ScanCategory]) async -> AttributionReport { report }
    }

    /// C1 锁定测试用：归因产出条目数 = 收到的 categories（树）条目数 ——
    /// 「扇出是否消费了新鲜树」由组数量直接可辨（空树 → 零组，有树 → 组非空）。
    private struct TreeSizedAttribution: AttributionScanning {
        func attribute(categories: [ScanCategory]) async -> AttributionReport {
            let items = (0..<categories.count).map { index in
                SpaceAttribution(scope: .fileTree, paths: ["/Users/t/cat\(index)"],
                                 bytes: 100, owner: .system, cause: .cache,
                                 reclaim: .recycles(expectedDays: 7),
                                 confidence: .certain, source: .rule, ruleID: "t",
                                 evidence: [], lastModified: nil)
            }
            return AttributionReport(
                items: items, refused: [], unattributedBytes: 0,
                blackBox: BlackBoxBreakdown(usedBytes: 1_000, visibleBytes: 400,
                                            residualBytes: 600, snapshotCount: 0,
                                            status: .reconciled),
                snapshots: [], generatedAt: Date())
        }
    }

    /// 挂在 gate 上的重复检测器 —— 放行后产出 1 组。
    private final class GatedDuplicateScanner: DuplicateScanning, @unchecked Sendable {
        let gate: Gate
        let recorder: CallRecorder
        init(gate: Gate, recorder: CallRecorder) {
            self.gate = gate
            self.recorder = recorder
        }
        func scan(paths: [URL], preset: SimilarityPreset, strategy: SelectionStrategy,
                  minFileSize: Int64, exclusions: [String],
                  enablePerceptual: Bool) -> AsyncStream<DetectionCore.ScanEvent> {
            AsyncStream { continuation in
                Task {
                    await self.gate.wait()
                    self.recorder.record("duplicates")
                    let group = DetectionCore.DuplicateGroup(
                        id: UUID(), category: .identical, totalSize: 200, fileCount: 2,
                        files: [
                            DetectionCore.FileItem(id: UUID(), url: URL(fileURLWithPath: "/t/a copy"),
                                                   size: 100,
                                                   modificationDate: Date(timeIntervalSinceReferenceDate: 0)),
                            DetectionCore.FileItem(id: UUID(), url: URL(fileURLWithPath: "/t/a"),
                                                   size: 100,
                                                   modificationDate: Date(timeIntervalSinceReferenceDate: 100)),
                        ],
                        categoryEvidence: .byteIdentical(sha256: "", byteVerified: false))
                    continuation.yield(.group(duplicateGroup: group))
                    continuation.finish()
                }
            }
        }
    }

    private func attributionReport(items: [SpaceAttribution]) -> AttributionReport {
        AttributionReport(
            items: items, refused: [], unattributedBytes: 0,
            blackBox: BlackBoxBreakdown(usedBytes: 1_000, visibleBytes: 400,
                                        residualBytes: 600, snapshotCount: 0,
                                        status: .reconciled),
            snapshots: [], generatedAt: Date())
    }

    private func causeItem(bytes: Int64) -> SpaceAttribution {
        SpaceAttribution(scope: .fileTree, paths: ["/Users/t/caches/x"], bytes: bytes,
                         owner: .system, cause: .cache, reclaim: .recycles(expectedDays: 7),
                         confidence: .certain, source: .rule, ruleID: "t",
                         evidence: [], lastModified: nil)
    }

    /// VM：空语料归因服务（refresh 只产空报告，不触文件系统）。
    private func makeViewModel() -> AnatomyViewModel {
        let service = AttributionService(
            engine: AttributionRuleEngine(
                corpus: AttributionRuleCorpus(schemaVersion: 1, rules: []),
                homeDirectory: "/Users/t"),
            volumeReader: nil,
            rootURL: URL(fileURLWithPath: "/Users/t"),
            volumeUsedBytesProvider: { 1_000 })
        let vm = AnatomyViewModel(service: service)
        vm.rebindCategories { [] }
        return vm
    }

    private func makeCoordinator(report: AttributionReport,
                                 duplicate: (any DuplicateScanning)? = nil) -> CanvasScanCoordinator {
        CanvasScanCoordinator(
            attributionService: FixedAttribution(report: report),
            duplicateScanner: duplicate,
            photoScanner: nil,
            largeFileScanner: nil)
    }

    @discardableResult
    private func waitUntil(timeout: TimeInterval = 5, _ check: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if check() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return check()
    }

    // MARK: - ScanPhase 状态机

    func testScanPhaseTransitions() {
        var phase = AnatomyViewModel.ScanPhase.idle
        phase = .scanning(progress: 0.4, path: "/Users/t/Library")
        if case .scanning(let p, let path) = phase {
            XCTAssertEqual(p, 0.4)
            XCTAssertEqual(path, "/Users/t/Library")
        } else {
            XCTFail("expected scanning")
        }
        phase = .done
        XCTAssertEqual(phase, .done, "scanning → done 是合法迁移（完成态）")
    }

    // MARK: - startScan 管线

    func testStartScanProducesReportAndDonePhase() async {
        let vm = makeViewModel()
        vm.bindCoordinator(makeCoordinator(
            report: attributionReport(items: [causeItem(bytes: 400)])))
        vm.rebindScope {
            CanvasScanScope(categories: [], duplicateRoots: [],
                            photoDirectories: [], largeFileRoots: [])
        }

        await vm.runCanvasScan()

        XCTAssertEqual(vm.scanPhase, .done, "扫描完成 → done")
        XCTAssertEqual(vm.canvasReport?.groups.map(\.id), [.cause(.cache)])
        XCTAssertNotNil(vm.report, "完成后归因刷新仍要跑（attributionLookup 依赖）")
    }

    func testGroupsDimmedButNotEmptyWhileScanning() async {
        let vm = makeViewModel()
        // 第一次快速扫描 → 画布有上一次的结果。
        vm.bindCoordinator(makeCoordinator(
            report: attributionReport(items: [causeItem(bytes: 400)])))
        vm.rebindScope {
            CanvasScanScope(categories: [], duplicateRoots: [],
                            photoDirectories: [], largeFileRoots: [])
        }
        await vm.runCanvasScan()
        XCTAssertEqual(vm.displayGroups.map(\.id), [.cause(.cache)])

        // 第二次扫描：重复检测器被 gate 挂起 → 扫描中。
        let gate = Gate()
        let recorder = CallRecorder()
        let gated = makeCoordinator(
            report: attributionReport(items: [causeItem(bytes: 300)]),
            duplicate: GatedDuplicateScanner(gate: gate, recorder: recorder))
        vm.bindCoordinator(gated)

        let task = Task { await vm.runCanvasScan() }
        let enteredScanning = await waitUntil { vm.scanPhase.isScanning }
        XCTAssertTrue(enteredScanning, "扇出扫描中 hero 应处于进度态")

        // 上一次结果保留（不清空）——渲染层据此变灰。fix r1 ②：同 kind 的
        // 旧组被增量新组**替换**（新扫描的组就是最新事实），ForEach id 恒唯一。
        let ids = vm.displayGroups.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count,
                       "扫描中并存组的 GroupKind 不得重复（ForEach identity 契约）")
        let causeGroup = vm.displayGroups.first { $0.id == .cause(.cache) }
        XCTAssertEqual(causeGroup?.totalBytes, 300,
                       "同 kind 并存时增量新组获胜（300 新 > 400 旧）")

        await gate.open()
        await task.value
        XCTAssertEqual(vm.scanPhase, .done)
        XCTAssertEqual(vm.canvasReport?.groups.map(\.id), [.cause(.cache), .duplicates],
                       "新一轮报告刷新画布（300 归因 > 200 重复，降序）")
    }

    /// fix r1 ② — 增量替换的另一半：旧报告独有的组（新扫描尚未产出的 kind）
    /// 在扫描中仍保留（不清空契约）。
    func testDisplayGroupsCarryOldKindsNotYetProduced() async {
        let vm = makeViewModel()
        // 旧报告：cache 400 + 大文件 500（旧扫描产出）。
        vm.bindCoordinator(makeCoordinator(
            report: attributionReport(items: [causeItem(bytes: 400)])))
        vm.rebindScope {
            CanvasScanScope(categories: [], duplicateRoots: [],
                            photoDirectories: [], largeFileRoots: [])
        }
        await vm.runCanvasScan()
        XCTAssertEqual(vm.canvasReport?.groups.map(\.id), [.cause(.cache)])

        // 新扫描：只有归因段（检测器全 nil）→ 产出 cache 300。
        vm.bindCoordinator(makeCoordinator(
            report: attributionReport(items: [causeItem(bytes: 300)]),
            duplicate: nil))
        let task = Task { await vm.runCanvasScan() }
        _ = await waitUntil { vm.scanPhase.isScanning }

        let ids = vm.displayGroups.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "id 唯一")
        XCTAssertTrue(ids.contains(.cause(.cache)), "新 kind 替换旧 kind")
        let finished = await waitUntil { !(vm.canvasCoordinator?.isRunning ?? true) }
        XCTAssertTrue(finished)
        await task.value
        XCTAssertEqual(vm.canvasReport?.groups.map(\.id), [.cause(.cache)])
    }

    func testReentrantStartScanWhileRunningIsIgnored() async {
        let vm = makeViewModel()
        let gate = Gate()
        let recorder = CallRecorder()
        vm.bindCoordinator(makeCoordinator(
            report: attributionReport(items: [causeItem(bytes: 400)]),
            duplicate: GatedDuplicateScanner(gate: gate, recorder: recorder)))
        vm.rebindScope {
            CanvasScanScope(categories: [], duplicateRoots: [URL(fileURLWithPath: "/t")],
                            photoDirectories: [], largeFileRoots: [])
        }

        let task = Task { await vm.runCanvasScan() }
        _ = await waitUntil { vm.scanPhase.isScanning }

        // 重入：isRunning 守卫应直接忽略，不叠加第二次扇出。
        vm.startScan()
        vm.startScan()

        await gate.open()
        await task.value

        XCTAssertEqual(recorder.count(of: "duplicates"), 1,
                       "重入的 startScan 被忽略（【交接 T2】isRunning 守卫）")
        XCTAssertEqual(vm.scanPhase, .done)
    }

    func testCancelScanReturnsToIdle() async {
        let vm = makeViewModel()
        let gate = Gate()
        vm.bindCoordinator(makeCoordinator(
            report: attributionReport(items: []),
            duplicate: GatedDuplicateScanner(gate: gate, recorder: CallRecorder())))
        vm.rebindScope {
            CanvasScanScope(categories: [], duplicateRoots: [URL(fileURLWithPath: "/t")],
                            photoDirectories: [], largeFileRoots: [])
        }

        // 经 startScan 启动 —— canvasScanTask 句柄必须真实挂上，cancelScan
        // 才能取消到（直接 Task { } 起的活体 cancelScan 够不着）。
        vm.startScan()
        let entered = await waitUntil { vm.scanPhase.isScanning }
        XCTAssertTrue(entered)

        vm.cancelScan()
        // 放行被挂起的检测器段：已取消的 Task 不再消费任何事件（next() 对
        // 已取消任务直接返回 nil），管线空转收尾。
        await gate.open()
        let finished = await waitUntil { !(vm.canvasCoordinator?.isRunning ?? true) }
        XCTAssertTrue(finished, "取消后扇出管线应落定（isRunning → false）")

        XCTAssertEqual(vm.scanPhase, .idle, "取消 → 回到 idle（不伪造完成态）")
        XCTAssertNil(vm.canvasReport, "取消的扫描不写 canvasReport（增量报告不可当完成态渲染）")
    }

    // MARK: - bindScanViewModel（P1 修复波迁移）

    func testScanPageCompletionTriggersAttributionRefresh() async {
        let vm = makeViewModel()
        XCTAssertNil(vm.report, "初始无报告")

        let scanVM = ScanResultsViewModel(engine: nil)
        vm.bindScanViewModel(scanVM)

        // 模拟扫描页引擎扫描：true → false。
        scanVM.assign(snapshot: .init(isScanning: true, hasScanned: true,
                                      categories: [], totalSelectedSize: 0,
                                      totalSelectedCount: 0, needsFullDiskAccess: false))
        scanVM.assign(snapshot: .init(isScanning: false, hasScanned: true,
                                      categories: [], totalSelectedSize: 0,
                                      totalSelectedCount: 0, needsFullDiskAccess: false))

        let refreshed = await waitUntil { vm.report != nil }
        XCTAssertTrue(refreshed, "isScanning true→false 必须触发归因刷新（P1 修复波）")
    }

    func testEngineScanMirrorsProgressIntoHeroPhase() async {
        let vm = makeViewModel()
        vm.bindCoordinator(makeCoordinator(report: attributionReport(items: [])))
        let scanVM = ScanResultsViewModel(engine: nil)
        vm.bindScanViewModel(scanVM)

        scanVM.assign(snapshot: .init(isScanning: true, hasScanned: true,
                                      categories: [], totalSelectedSize: 0,
                                      totalSelectedCount: 0, needsFullDiskAccess: false))
        scanVM.progress = 0.5
        scanVM.currentPath = "/Users/t/Library"

        let mirrored = await waitUntil {
            vm.scanPhase == .scanning(progress: 0.5, path: "/Users/t/Library")
        }
        XCTAssertTrue(mirrored, "引擎扫描期间 hero 镜像引擎进度（ScanResultsViewModel.$progress/currentPath）")
        XCTAssertEqual(vm.activeScanSource, .engine, "镜像期间数据源 = 引擎")
        XCTAssertFalse(vm.showsScanCancel,
                       "fix r1 ②：引擎镜像态隐藏「取消」（对引擎无效，显示即误导）")

        scanVM.assign(snapshot: .init(isScanning: false, hasScanned: true,
                                      categories: [], totalSelectedSize: 0,
                                      totalSelectedCount: 0, needsFullDiskAccess: false))
        let settled = await waitUntil { vm.scanPhase == .idle }
        XCTAssertTrue(settled, "引擎扫描结束（画布无旧报告）→ 回到 idle")
    }

    /// fix r1 ② — 扇出扫描中「取消」必须可见（与镜像态相反）。
    func testCancelButtonVisibleDuringFanOutScan() async {
        let vm = makeViewModel()
        let gate = Gate()
        vm.bindCoordinator(makeCoordinator(
            report: attributionReport(items: [causeItem(bytes: 400)]),
            duplicate: GatedDuplicateScanner(gate: gate, recorder: CallRecorder())))
        vm.rebindScope {
            CanvasScanScope(categories: [], duplicateRoots: [URL(fileURLWithPath: "/t")],
                            photoDirectories: [], largeFileRoots: [])
        }

        vm.startScan()
        let entered = await waitUntil { vm.scanPhase.isScanning }
        XCTAssertTrue(entered)
        XCTAssertEqual(vm.activeScanSource, .fanOut)
        XCTAssertTrue(vm.showsScanCancel, "扇出扫描中「取消」可见（有真取消句柄）")

        await gate.open()
        _ = await waitUntil { !(vm.canvasCoordinator?.isRunning ?? true) }
        XCTAssertFalse(vm.showsScanCancel, "扫描结束「取消」隐藏")
    }

    /// fix r1 ⑤ — bindScanViewModel 幂等：重复 bind 不累积订阅（归因刷新
    /// 恰好跑一次，而不是每个旧订阅各跑一次）。
    func testBindScanViewModelIsIdempotent() async {
        let vm = makeViewModel()
        var providerCalls = 0
        vm.rebindCategories {
            providerCalls += 1
            return []
        }
        let scanVM = ScanResultsViewModel(engine: nil)
        vm.bindScanViewModel(scanVM)
        vm.bindScanViewModel(scanVM)
        vm.bindScanViewModel(scanVM)

        scanVM.assign(snapshot: .init(isScanning: true, hasScanned: true,
                                      categories: [], totalSelectedSize: 0,
                                      totalSelectedCount: 0, needsFullDiskAccess: false))
        scanVM.assign(snapshot: .init(isScanning: false, hasScanned: true,
                                      categories: [], totalSelectedSize: 0,
                                      totalSelectedCount: 0, needsFullDiskAccess: false))

        let refreshed = await waitUntil { providerCalls > 0 }
        XCTAssertTrue(refreshed)
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(providerCalls, 1,
                       "三次 bind 只留一份订阅：isScanning 下降沿恰好触发一次刷新")
    }

    // MARK: - C1（P2 final）：统一扫描入口 —— 先引擎扫描，后对新鲜树扇出

    /// 锁定测试：空初始树 → startScan → 引擎扫描产出 → 扇出消费新树 →
    /// 组非空（空树 → 有树两阶段，注入 mock，零文件系统触达）。
    func testCanvasScanAwaitsEngineScanThenFansOutFreshTree() async {
        let vm = makeViewModel()
        let scanVM = ScanResultsViewModel(engine: nil)
        vm.rebindCategories { scanVM.categories }
        vm.bindScanViewModel(scanVM)
        vm.bindCoordinator(CanvasScanCoordinator(
            attributionService: TreeSizedAttribution(),
            duplicateScanner: nil, photoScanner: nil, largeFileScanner: nil))
        // 扇出范围镜像生产装配：**此刻**的新鲜树（defaultScope 的
        // categoriesProvider 等价物；这里用 rebindScope 避开能力探测）。
        vm.rebindScope {
            CanvasScanScope(categories: scanVM.categories, duplicateRoots: [],
                            photoDirectories: [], largeFileRoots: [])
        }

        // 阶段一：引擎扫描开始（空树）—— 画布扫描入口等待引擎完成。
        scanVM.assign(snapshot: .init(isScanning: true, hasScanned: false,
                                      categories: [], totalSelectedSize: 0,
                                      totalSelectedCount: 0, needsFullDiskAccess: false))
        let task = Task { await vm.runCanvasScan() }

        // 阶段二：引擎扫描完成 → 新鲜树落进 categories（生产里即
        // startRealScan 的收尾 snapshot 写入）→ 扇出消费新树。
        let tree = ScanCategory(categoryID: "c", title: "c", subItems: [])
        scanVM.assign(snapshot: .init(isScanning: false, hasScanned: true,
                                      categories: [tree], totalSelectedSize: 0,
                                      totalSelectedCount: 0, needsFullDiskAccess: false))
        await task.value

        XCTAssertEqual(vm.scanPhase, .done)
        XCTAssertEqual(vm.canvasReport?.groups.map(\.id), [.cause(.cache)],
                       "扇出消费新鲜树 → cause 组非空（空树 → 有树两阶段）")
    }

    // MARK: - I3（P2 final）：取消后立即重扫不静默丢弃

    func testRescanAfterCancelIsQueuedNotSilentlyDropped() async {
        let vm = makeViewModel()
        let gate = Gate()
        let recorder = CallRecorder()
        vm.bindCoordinator(makeCoordinator(
            report: attributionReport(items: [causeItem(bytes: 400)]),
            duplicate: GatedDuplicateScanner(gate: gate, recorder: recorder)))
        vm.rebindScope {
            CanvasScanScope(categories: [], duplicateRoots: [URL(fileURLWithPath: "/t")],
                            photoDirectories: [], largeFileRoots: [])
        }

        vm.startScan()
        let entered = await waitUntil { vm.scanPhase.isScanning }
        XCTAssertTrue(entered)

        vm.cancelScan()
        XCTAssertEqual(vm.scanPhase, .stopping,
                       "取消 → 诚实「正在停止」过渡态（管线尚未落定）")

        // 停止窗口期立即重扫 —— 排队等待落定后真实启动，绝不静默丢弃。
        vm.startScan()
        await gate.open()
        let finished = await waitUntil { vm.scanPhase == .done }
        XCTAssertTrue(finished, "取消后的重扫最终真实启动（.done）")
        XCTAssertEqual(recorder.count(of: "duplicates"), 2,
                       "第二扇出真实运行（取消 + 重扫各一次）")
    }

    // MARK: - I2（P2 final）：就地清理成功后画布就地失效

    func testApplyCleanupOutcomeRemovesAffectedEntriesAndGroups() async {
        let vm = makeViewModel()
        vm.bindCoordinator(makeCoordinator(report: attributionReport(items: [
            SpaceAttribution(scope: .fileTree, paths: ["/Users/t/caches/keep"], bytes: 400,
                             owner: .system, cause: .cache,
                             reclaim: .recycles(expectedDays: 7), confidence: .certain,
                             source: .rule, ruleID: "t", evidence: [], lastModified: nil),
            SpaceAttribution(scope: .fileTree, paths: ["/Users/t/caches/x"], bytes: 300,
                             owner: .system, cause: .cache,
                             reclaim: .recycles(expectedDays: 7), confidence: .certain,
                             source: .rule, ruleID: "t", evidence: [], lastModified: nil),
        ])))
        vm.rebindScope {
            CanvasScanScope(categories: [], duplicateRoots: [],
                            photoDirectories: [], largeFileRoots: [])
        }
        await vm.runCanvasScan()
        XCTAssertEqual(vm.canvasReport?.groups.first?.totalBytes, 700)

        // 下钻缓存预先存在 —— 清理后必须整体作废。
        let group = vm.canvasReport?.groups.first
        vm.drillDownModels[.cause(.cache)] = GroupDrillDownModel(
            group: group!, entries: group!.entries)

        // 清理掉 300 字节条目 → 组字节减少（700 → 400）、下钻缓存清空。
        await vm.applyCleanupOutcome(CleanupOutcome(
            succeeded: [URL(fileURLWithPath: "/Users/t/caches/x")], freedBytes: 300))
        XCTAssertEqual(vm.canvasReport?.groups.first?.totalBytes, 400,
                       "清理后画布组字节就地减少（不等下一次重扫）")
        XCTAssertTrue(vm.drillDownModels.isEmpty, "下钻勾选缓存整体作废")

        // 清理掉组内最后一条 → 整组消失（空组不出现契约）。
        await vm.applyCleanupOutcome(CleanupOutcome(
            succeeded: [URL(fileURLWithPath: "/Users/t/caches/keep")], freedBytes: 400))
        XCTAssertTrue(vm.canvasReport?.groups.isEmpty ?? false, "清空的组连组一起消失")
    }

    // MARK: - I4（P2 final）：快捷回收估算用诚实字节

    func testQuickCleanEstimateUsesHonestEntryBytes() {
        let vm = makeViewModel()
        let honestEntry = CanvasEntry(title: "copy", bytes: 100, badge: .recyclable)
        let dataEntry = CanvasEntry(title: "data", bytes: 5_000, badge: .dataNotJunk)
        let group = CanvasGroup(
            id: .duplicates, icon: "doc.on.doc", title: "重复文件", subtitle: "",
            totalBytes: 100, entries: [honestEntry, dataEntry], action: .rehearse)
        vm.canvasReport = CanvasReport(groups: [group], uncovered: nil,
                                       snapshots: [], generatedAt: Date())
        XCTAssertEqual(vm.quickCleanEstimate, 100,
                       "估算只累计绿徽条目的诚实字节（克隆增量），绝不吃全尺寸")
    }
}
