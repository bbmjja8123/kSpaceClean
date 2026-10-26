// kWise/Tests/CanvasScanCoordinatorTests.swift
//
// P2 T2 — 扇出扫描协调器（全部注入 mock，不触碰真实文件系统）：
// - 扇出顺序：归因 → 重复 → 照片 → 大文件
// - 每组完成即产出（增量）：归因组先于检测器组可见
// - 单检测器 nil（未授权/关闭）→ 该组跳过；全部 nil → 仅归因组
// - 检测器产空结果 → 空组不出现
import XCTest
import DetectionCore
@testable import kWise

// MARK: - 测试基建

/// 线程安全的调用顺序记录器。
private final class CallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func record(_ call: String) { lock.withLock { items.append(call) } }
    var calls: [String] { lock.withLock { items } }
}

/// 挂起检测器直到测试放行 —— 用于验证「每组完成即产出」。
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

private final class MockAttribution: AttributionScanning {
    let report: AttributionReport
    let recorder: CallRecorder
    init(report: AttributionReport, recorder: CallRecorder) {
        self.report = report
        self.recorder = recorder
    }
    func attribute(categories: [ScanCategory]) async -> AttributionReport {
        recorder.record("attribution")
        return report
    }
}

private final class MockDuplicateScanner: DuplicateScanning, @unchecked Sendable {
    let recorder: CallRecorder
    let gate: Gate?
    private let size: Int64
    private let failureMessage: String?
    private let warningMessage: String?
    init(recorder: CallRecorder, size: Int64 = 100, gate: Gate? = nil,
         failureMessage: String? = nil, warningMessage: String? = nil) {
        self.recorder = recorder
        self.gate = gate
        self.size = size
        self.failureMessage = failureMessage
        self.warningMessage = warningMessage
    }
    func scan(paths: [URL], preset: SimilarityPreset, strategy: SelectionStrategy,
              minFileSize: Int64, exclusions: [String],
              enablePerceptual: Bool) -> AsyncStream<DetectionCore.ScanEvent> {
        AsyncStream { continuation in
            Task {
                await self.gate?.wait()
                self.recorder.record("duplicates")
                // size == 0 且无 failure/warning 模拟「检测器跑了但一无所获」。
                guard self.size > 0 || self.failureMessage != nil
                        || self.warningMessage != nil else {
                    continuation.finish()
                    return
                }
                if let warning = self.warningMessage {
                    continuation.yield(.warning(DetectionCore.ScanWarning(
                        message: warning, phase: .enumerating)))
                }
                if let failure = self.failureMessage {
                    continuation.yield(.failed(failure))
                    continuation.finish()
                    return
                }
                let group = DetectionCore.DuplicateGroup(
                    id: UUID(), category: .identical, totalSize: self.size * 2,
                    fileCount: 2,
                    files: [
                        DetectionCore.FileItem(id: UUID(), url: URL(fileURLWithPath: "/t/a copy"),
                                               size: self.size,
                                               modificationDate: Date(timeIntervalSinceReferenceDate: 0)),
                        DetectionCore.FileItem(id: UUID(), url: URL(fileURLWithPath: "/t/a"),
                                               size: self.size,
                                               modificationDate: Date(timeIntervalSinceReferenceDate: 100)),
                    ],
                    categoryEvidence: .byteIdentical(sha256: "", byteVerified: false))
                continuation.yield(.group(duplicateGroup: group))
                continuation.finish()
            }
        }
    }
}

private final class MockPhotoScanner: PhotoScanning, @unchecked Sendable {
    let recorder: CallRecorder
    let groups: [DetectionCore.DuplicateGroup]
    init(recorder: CallRecorder, groups: [DetectionCore.DuplicateGroup]) {
        self.recorder = recorder
        self.groups = groups
    }
    func scan(config: PhotoSimilarityConfig, controller: ScanController,
              progress: @escaping @Sendable (Double, String?) -> Void)
        async -> [DetectionCore.DuplicateGroup] {
        recorder.record("photos")
        return groups
    }
}

private final class MockLargeFileScanner: LargeFileScanning, @unchecked Sendable {
    let recorder: CallRecorder
    let entries: [LargeOldFileEntry]
    init(recorder: CallRecorder, entries: [LargeOldFileEntry]) {
        self.recorder = recorder
        self.entries = entries
    }
    func scan(config: LargeOldScanConfig) -> AsyncStream<LargeOldFileEntry> {
        AsyncStream { continuation in
            Task {
                self.recorder.record("largeFiles")
                for entry in self.entries { continuation.yield(entry) }
                continuation.finish()
            }
        }
    }
}

/// Task 8 家务检测 mock：`homeURL == nil` 模拟 container-only（诚实返回空，
/// 诊断由 coordinator 负责 —— 与真实现同契约）。
private final class MockHousekeepingScanner: HousekeepingScanning, @unchecked Sendable {
    let recorder: CallRecorder
    let findings: [HousekeepingFinding]
    init(recorder: CallRecorder, findings: [HousekeepingFinding]) {
        self.recorder = recorder
        self.findings = findings
    }
    func scan(homeURL: URL?) async -> [HousekeepingFinding] {
        recorder.record("housekeeping")
        guard homeURL != nil else { return [] }
        return findings
    }
}

// MARK: - Tests

@MainActor
final class CanvasScanCoordinatorTests: XCTestCase {

    private let recorder = CallRecorder()

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

    private func makeCoordinator(report: AttributionReport,
                                 duplicate: (any DuplicateScanning)?,
                                 photo: (any PhotoScanning)?,
                                 large: (any LargeFileScanning)?,
                                 housekeeping: (any HousekeepingScanning)? = nil)
        -> CanvasScanCoordinator {
        CanvasScanCoordinator(
            attributionService: MockAttribution(report: report, recorder: recorder),
            duplicateScanner: duplicate,
            photoScanner: photo,
            largeFileScanner: large,
            housekeepingScanner: housekeeping)
    }

    private func scope() -> CanvasScanScope {
        // housekeepingHome 指向不存在的路径 → 真检测器（若被注入）也返回空；
        // nil 语义留给 container-only 专项测试（上 skippedHousekeeping 诊断）。
        CanvasScanScope(categories: [], duplicateRoots: [URL(fileURLWithPath: "/t")],
                        photoDirectories: [URL(fileURLWithPath: "/t")],
                        largeFileRoots: [URL(fileURLWithPath: "/t")],
                        housekeepingHome: URL(fileURLWithPath: "/t"))
    }

    private func photoGroup(size: Int64) -> DetectionCore.DuplicateGroup {
        DetectionCore.DuplicateGroup(
            id: UUID(), category: .perceptual, totalSize: size * 2, fileCount: 2,
            files: [
                DetectionCore.FileItem(id: UUID(), url: URL(fileURLWithPath: "/t/p1.jpg"),
                                       size: size,
                                       modificationDate: Date(timeIntervalSinceReferenceDate: 0)),
                DetectionCore.FileItem(id: UUID(), url: URL(fileURLWithPath: "/t/p2.jpg"),
                                       size: size,
                                       modificationDate: Date(timeIntervalSinceReferenceDate: 100)),
            ],
            categoryEvidence: .perceptualSimilarity(distance: 0.1, method: .dHash))
    }

    // MARK: 扇出顺序

    func testFanOutOrderAttributionDuplicatesPhotosLargeFiles() async {
        let coordinator = makeCoordinator(
            report: attributionReport(items: [causeItem(bytes: 400)]),
            duplicate: MockDuplicateScanner(recorder: recorder, size: 100),
            photo: MockPhotoScanner(recorder: recorder, groups: [photoGroup(size: 200)]),
            large: MockLargeFileScanner(recorder: recorder, entries: [
                LargeOldFileEntry(url: URL(fileURLWithPath: "/t/big.mov"), size: 1_000,
                                  modificationDate: Date()),
            ]))
        let report = await coordinator.runScan(scope: scope())

        XCTAssertEqual(recorder.calls, ["attribution", "duplicates", "photos", "largeFiles"],
                       "扇出顺序：归因 → 重复 → 照片 → 大文件（spec §5）")
        // 报告按 totalBytes 降序（fix r1 ③）；增量填充顺序见 incremental 测试。
        XCTAssertEqual(report.groups.map(\.id),
                       [.largeFiles, .cause(.cache), .similarPhotos, .duplicates],
                       "报告组按 totalBytes 降序（1000/400/200/100）")
    }

    // MARK: 增量产出

    func testGroupsAppearIncrementallyWhileDetectorsRun() async {
        let gate = Gate()
        let coordinator = makeCoordinator(
            report: attributionReport(items: [causeItem(bytes: 400)]),
            duplicate: MockDuplicateScanner(recorder: recorder, size: 100, gate: gate),
            photo: nil,
            large: nil)

        let runTask = Task { await coordinator.runScan(scope: scope()) }

        // 等归因组先上画布（重复检测器仍被 gate 挂起）。
        let deadline = Date().addingTimeInterval(5)
        while coordinator.groups.isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(coordinator.groups.map(\.id), [.cause(.cache)],
                       "归因组先于检测器组可见（增量产出，画布不清空）")

        await gate.open()
        let report = await runTask.value
        XCTAssertEqual(report.groups.map(\.id), [.cause(.cache), .duplicates])
    }

    // MARK: 检测器 nil / 空结果

    func testSingleNilDetectorSkipsOnlyItsGroup() async {
        let coordinator = makeCoordinator(
            report: attributionReport(items: [causeItem(bytes: 400)]),
            duplicate: MockDuplicateScanner(recorder: recorder, size: 100),
            photo: nil, // 相似照片：未授权 / 已关闭
            large: MockLargeFileScanner(recorder: recorder, entries: [
                LargeOldFileEntry(url: URL(fileURLWithPath: "/t/big.mov"), size: 1_000,
                                  modificationDate: Date()),
            ]))
        let report = await coordinator.runScan(scope: scope())

        XCTAssertEqual(report.groups.map(\.id), [.largeFiles, .cause(.cache), .duplicates],
                       "photo 检测器为 nil → 该组跳过，不出空组（报告按字节降序）")
    }

    func testAllDetectorsNilYieldsAttributionGroupsOnly() async {
        let coordinator = makeCoordinator(
            report: attributionReport(items: [causeItem(bytes: 400)]),
            duplicate: nil, photo: nil, large: nil)
        let report = await coordinator.runScan(scope: scope())

        XCTAssertEqual(report.groups.map(\.id), [.cause(.cache)],
                       "全部检测器 nil → 仅归因组")
    }

    func testEmptyDetectorResultsProduceNoGroups() async {
        let coordinator = makeCoordinator(
            report: attributionReport(items: []),
            duplicate: MockDuplicateScanner(recorder: recorder, size: 0),
            photo: MockPhotoScanner(recorder: recorder, groups: []),
            large: MockLargeFileScanner(recorder: recorder, entries: []))
        let report = await coordinator.runScan(scope: scope())

        XCTAssertTrue(report.groups.isEmpty, "检测结果为空的组一律不出现")
    }

    // MARK: 报告载荷

    func testReportCarriesUncoveredAndSnapshots() async {
        let coordinator = makeCoordinator(
            report: attributionReport(items: [causeItem(bytes: 400)]),
            duplicate: nil, photo: nil, large: nil)
        let report = await coordinator.runScan(scope: scope())

        XCTAssertEqual(report.uncovered?.residualBytes, 600)
        XCTAssertNotNil(report.snapshots)
        XCTAssertEqual(report.groups.count, 1)
    }

    func testRefusedDerivedToUncertainCardNotCanvasGroup() async {
        let refusedItem = SpaceAttribution(
            scope: .fileTree, paths: ["/Users/t/mystery"], bytes: 900_000_000,
            owner: .unknown, cause: .unknown, reclaim: .uncertain,
            confidence: .refused, source: .unattributed, ruleID: nil,
            evidence: [], lastModified: nil)
        var report = attributionReport(items: [causeItem(bytes: 400)])
        report = AttributionReport(
            items: report.items, refused: [refusedItem],
            unattributedBytes: 0, blackBox: report.blackBox,
            snapshots: report.snapshots, generatedAt: Date())

        let coordinator = makeCoordinator(report: report,
                                          duplicate: nil, photo: nil, large: nil)
        let canvasReport = await coordinator.runScan(scope: scope())

        XCTAssertFalse(canvasReport.groups.contains { $0.id == .cause(.unknown) },
                       "拒答项不占 CanvasGroup")
        XCTAssertEqual(coordinator.uncertainCard?.totalBytes, 900_000_000,
                       "「我不敢判的」派生为虚线卡数据")
    }

    // MARK: 诊断通道（fix r1）

    func testFailedEventSurfacesInDiagnostics() async {
        let coordinator = makeCoordinator(
            report: attributionReport(items: []),
            duplicate: MockDuplicateScanner(recorder: recorder, size: 0,
                                            failureMessage: "engine exploded mid-walk"),
            photo: nil, large: nil)
        let report = await coordinator.runScan(scope: scope())

        XCTAssertTrue(report.groups.isEmpty, "管线失败 → 该组不出现")
        XCTAssertEqual(coordinator.scanDiagnostics, ["engine exploded mid-walk"],
                       ".failed 不再被静默丢弃 —— T3 可显示降级态文案")
    }

    func testWarningEventSurfacesInDiagnostics() async {
        let coordinator = makeCoordinator(
            report: attributionReport(items: []),
            duplicate: MockDuplicateScanner(recorder: recorder, size: 0,
                                            warningMessage: "unreadable path skipped"),
            photo: nil, large: nil)
        _ = await coordinator.runScan(scope: scope())

        XCTAssertEqual(coordinator.scanDiagnostics, ["unreadable path skipped"],
                       ".warning 同样进诊断通道（诚实降级）")
    }

    func testReentrantRunScanIsIgnoredWithDiagnostic() async {
        let gate = Gate()
        let coordinator = makeCoordinator(
            report: attributionReport(items: [causeItem(bytes: 400)]),
            duplicate: MockDuplicateScanner(recorder: recorder, size: 100, gate: gate),
            photo: nil, large: nil)

        let first = Task { await coordinator.runScan(scope: scope()) }
        // 等 first 进入 duplicate 段（gate 挂起中）。
        let deadline = Date().addingTimeInterval(5)
        while coordinator.groups.isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(coordinator.isRunning)

        // 重入：直接 return 并记诊断，不打断进行中的扫描。
        let second = await coordinator.runScan(scope: scope())
        XCTAssertTrue(coordinator.scanDiagnostics.contains { !$0.isEmpty },
                      "重入被记录为诊断信息")
        XCTAssertEqual(second.groups.map(\.id), [.cause(.cache)],
                       "重入返回当前（增量）状态，不重新清空画布")

        await gate.open()
        _ = await first.value
        XCTAssertFalse(coordinator.isRunning)
    }

    // MARK: 家务第五缝（Task 8）

    func testHousekeepingGroupAppendedAfterLargeFiles() async {
        let finding = HousekeepingFinding(kind: .trashLargeItems,
                                          url: URL(fileURLWithPath: "/t/.Trash/big.dmg"),
                                          title: "big.dmg", bytes: 30_000_000,
                                          daysIdle: nil)
        let coordinator = makeCoordinator(
            report: attributionReport(items: []),
            duplicate: nil, photo: nil, large: nil,
            housekeeping: MockHousekeepingScanner(recorder: recorder, findings: [finding]))
        let report = await coordinator.runScan(scope: scope())

        XCTAssertEqual(recorder.calls, ["attribution", "housekeeping"],
                       "家务是第五缝：归因之后（其余检测器 nil 时紧随归因）")
        XCTAssertEqual(report.groups.map(\.id), [.housekeeping(.trashLargeItems)],
                       "家务 findings 组装为 CanvasGroup，空 kind 不出现")
    }

    func testContainerOnlyHousekeepingNotSilentlyDropped() async {
        let coordinator = makeCoordinator(
            report: attributionReport(items: []),
            duplicate: nil, photo: nil, large: nil,
            housekeeping: MockHousekeepingScanner(recorder: recorder, findings: []))
        var containerOnlyScope = scope()
        containerOnlyScope.housekeepingHome = nil

        let report = await coordinator.runScan(scope: containerOnlyScope)

        XCTAssertTrue(report.groups.isEmpty, "container-only → 不出家务组（诚实降级）")
        XCTAssertEqual(coordinator.scanDiagnostics.count, 1,
                       "container-only 家务跳过必须可见（禁止静默丢弃，R2 先例）")
    }
}
