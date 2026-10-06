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
    init(recorder: CallRecorder, size: Int64 = 100, gate: Gate? = nil) {
        self.recorder = recorder
        self.gate = gate
        self.size = size
    }
    func scan(paths: [URL], preset: SimilarityPreset, strategy: SelectionStrategy,
              minFileSize: Int64, exclusions: [String],
              enablePerceptual: Bool) -> AsyncStream<DetectionCore.ScanEvent> {
        AsyncStream { continuation in
            Task {
                await self.gate?.wait()
                self.recorder.record("duplicates")
                // size == 0 模拟「检测器跑了但一无所获」。
                guard self.size > 0 else {
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
                                 large: (any LargeFileScanning)?) -> CanvasScanCoordinator {
        CanvasScanCoordinator(
            attributionService: MockAttribution(report: report, recorder: recorder),
            duplicateScanner: duplicate,
            photoScanner: photo,
            largeFileScanner: large)
    }

    private func scope() -> CanvasScanScope {
        CanvasScanScope(categories: [], duplicateRoots: [URL(fileURLWithPath: "/t")],
                        photoDirectories: [URL(fileURLWithPath: "/t")],
                        largeFileRoots: [URL(fileURLWithPath: "/t")])
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
        XCTAssertEqual(report.groups.map(\.id),
                       [.cause(.cache), .duplicates, .similarPhotos, .largeFiles],
                       "每组完成即产出，顺序即完成顺序")
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

        XCTAssertEqual(report.groups.map(\.id), [.cause(.cache), .duplicates, .largeFiles],
                       "photo 检测器为 nil → 该组跳过，不出空组")
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
}
