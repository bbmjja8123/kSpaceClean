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

        // 上一次结果保留（不清空）——渲染层据此变灰。displayGroups = 旧报告
        // 的组 + 协调器已增量产出的新归因组（同 cause 各一份：旧 400 / 新 300）。
        XCTAssertEqual(vm.displayGroups.first?.id, .cause(.cache),
                       "扫描中上一次结果保留（spec §5：淡出但不清空）")
        XCTAssertGreaterThanOrEqual(vm.displayGroups.count, 2,
                                    "协调器增量组与旧报告并存")

        await gate.open()
        await task.value
        XCTAssertEqual(vm.scanPhase, .done)
        XCTAssertEqual(vm.canvasReport?.groups.map(\.id), [.cause(.cache), .duplicates],
                       "新一轮报告刷新画布（300 归因 > 200 重复，降序）")
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

        scanVM.assign(snapshot: .init(isScanning: false, hasScanned: true,
                                      categories: [], totalSelectedSize: 0,
                                      totalSelectedCount: 0, needsFullDiskAccess: false))
        let settled = await waitUntil { vm.scanPhase == .idle }
        XCTAssertTrue(settled, "引擎扫描结束（画布无旧报告）→ 回到 idle")
    }
}
