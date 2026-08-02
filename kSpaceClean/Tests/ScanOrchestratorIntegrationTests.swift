// kSpaceClean/Tests/ScanOrchestratorIntegrationTests.swift
//
// E2E integration test for the production scan pipeline.
//
// Drives `ScanOrchestrator` directly against a real on-disk fixture under
// `/tmp/sclean-fixture-integration-<UUID>/` and asserts that:
//   * the per-category worker returns non-zero results for a known file
//   * the `categoryStream()` event surface matches the snapshot contents
//   * a second startScan() works on the same orchestrator instance after
//     the C2 reset path
//
// This is the only test that exercises the whole pipeline
// (RiskClassifier + BundleIDResolver + FileEnumerator + ScanOrchestrator)
// end-to-end rather than the head of each module in isolation. It exists
// because the v1.0 whole-branch review found 7 critical issues all
// rooted in the integration layer never being exercised; this test
// would have caught at least three of them on first run.
import XCTest
import FileScanner
@testable import kSpaceClean

@MainActor
final class ScanOrchestratorIntegrationTests: XCTestCase {

    /// Top-level fixture root. Resolved once per test invocation.
    private var fixtureRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        let root = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("sclean-fixture-integration-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        fixtureRoot = root

        // Single tiny file in the fixture's "app cache" subtree — large
        // enough to round-trip through FileManager resourceValues.
        let caches = root.appendingPathComponent("Caches/com.example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try Data(repeating: 0xCA, count: 256).write(to: caches.appendingPathComponent("dataless.bin"))
    }

    override func tearDown() async throws {
        if let root = fixtureRoot {
            try? FileManager.default.removeItem(at: root)
        }
        try await super.tearDown()
    }

    // MARK: - Happy path: fixture is enumerated and surfaces in the category stream

    func testOrchestratorYieldsFixtureFileInCategoryStream() async throws {
        let cats = [
            CategoryDefinition(
                id: "fixture.cache",
                title: "Fixture Cache",
                paths: [fixtureRoot.appendingPathComponent("Caches").path],
                riskLevel: .recommended
            )
        ]
        let orchestrator = ScanOrchestrator(categoryDefinitions: cats)

        // Drive the scan; break on terminal snapshot. The category-stream
        // consumer attaches AFTER startScan(): `categoryStream()` snapshots
        // the scan epoch at attach time, so a pre-startScan consumer would
        // capture the stale epoch and terminate immediately.
        let stream = await orchestrator.startScan()

        var emittedCategory: ScanCategoryEvent?
        var sawTerminalCompletion = false
        let consumer = Task { @MainActor in
            for await event in await orchestrator.categoryStream() {
                switch event {
                case .category(let catEvent):
                    emittedCategory = catEvent
                case .terminal(let progress):
                    if case .completed = progress.state {
                        sawTerminalCompletion = true
                    }
                    if case .failed = progress.state {
                        XCTFail("scan should not fail against a real fixture")
                    }
                }
            }
        }

        for await p in stream {
            if case .completed = p.state { break }
            if case .failed = p.state { XCTFail("scan failed") }
        }
        await consumer.value

        XCTAssertTrue(sawTerminalCompletion,
                      "categoryStream must emit a terminal `.completed` when the scan finishes")
        let cat = try XCTUnwrap(emittedCategory,
                                "orchestrator must publish the scan category to its stream")
        XCTAssertEqual(cat.category.title, "Fixture Cache")
        XCTAssertGreaterThan(cat.totalSize, 0,
                             "enumerator must report a nonzero size for the 256-byte fixture file")
    }

    // MARK: - C2 fix: second scan on the same orchestrator must reset cleanly

    func testSecondScanResetsCategoryStreamBuffers() async throws {
        let cats = [
            CategoryDefinition(
                id: "fixture.cache",
                title: "Fixture Cache",
                paths: [fixtureRoot.appendingPathComponent("Caches").path]
            )
        ]
        let orchestrator = ScanOrchestrator(categoryDefinitions: cats)

        // First scan: consume to terminal.
        let firstStream = await orchestrator.startScan()
        for await _ in firstStream { /* drain */ }

        // Second scan: must still emit a terminal event (regression
        // guard for the C2 bug where pendingCategoryEvents was never
        // cleared between scans). The consumer attaches AFTER the second
        // startScan() so it captures the new scan epoch, not the first
        // scan's (now-stale) epoch.
        let secondStream = await orchestrator.startScan()

        var sawTerminalCompletion = false
        let consumer = Task { @MainActor in
            for await event in await orchestrator.categoryStream() {
                if case .terminal(let p) = event, case .completed = p.state {
                    sawTerminalCompletion = true
                }
            }
        }
        for await p in secondStream {
            if case .completed = p.state { break }
        }
        await consumer.value

        XCTAssertTrue(sawTerminalCompletion,
                      "second scan on the same orchestrator must still emit a categoryStream terminal event")
    }

    // MARK: - Cancellation: stream finishes with a `.completed` or `.failed` sentinel

    func testCancellationFinishesCategoryStream() async throws {
        let cats = [
            CategoryDefinition(
                id: "fixture.a",
                title: "A",
                paths: [fixtureRoot.appendingPathComponent("Caches").path]
            ),
            CategoryDefinition(
                id: "fixture.b",
                title: "B",
                paths: [fixtureRoot.appendingPathComponent("Caches").path]
            )
        ]
        let orchestrator = ScanOrchestrator(categoryDefinitions: cats)

        // Consumer attaches after startScan() (epoch capture), before
        // cancel() so it observes the cancellation path.
        let stream = await orchestrator.startScan()

        var sawTerminal = false
        let consumer = Task { @MainActor in
            for await event in await orchestrator.categoryStream() {
                if case .terminal = event { sawTerminal = true }
            }
        }
        await orchestrator.cancel()
        for await _ in stream { /* drain until termination */ }

        await consumer.value
        XCTAssertTrue(sawTerminal,
                      "categoryStream must emit a terminal sentinel even when cancellation pre-empts the scan")
    }

    // MARK: - FileEnumerator: bounded stream

    func testFileEnumeratorEnumeratesFixture() async throws {
        let enumerator = FileEnumerator()
        let stream = await enumerator.enumerate(
            rootPath: fixtureRoot.appendingPathComponent("Caches").path
        )

        var emittedCount = 0
        var sawFixtureFile = false
        for await info in stream {
            emittedCount += 1
            if info.path.hasSuffix("dataless.bin") {
                sawFixtureFile = true
            }
        }
        XCTAssertGreaterThan(emittedCount, 0, "FileEnumerator should yield the fixture entries")
        XCTAssertTrue(sawFixtureFile,
                      "FileEnumerator must surface the fixture's dataless.bin path")
    }
}

/// Task A1 — live progress composer. Drives a scan over a 5000-file fixture
/// and asserts the interim `.scanning` snapshots carry real-time stats
/// (the complaint: the ring froze near 0 until the final yield).
@MainActor
final class ScanProgressComposerTests: XCTestCase {
    private var a1Root: URL!
    private var cachesRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        let root = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("sclean-a1-progress-\(UUID().uuidString)", isDirectory: true)
        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        for i in 0..<5000 {
            try Data(repeating: 0x01, count: 256)
                .write(to: caches.appendingPathComponent("f\(i).bin"))
        }
        a1Root = root
        cachesRoot = caches
    }

    override func tearDown() async throws {
        if let root = a1Root {
            try? FileManager.default.removeItem(at: root)
        }
        try await super.tearDown()
    }

    private func scanToCompletion(_ orchestrator: ScanOrchestrator) async -> [ScanProgress] {
        let stream = await orchestrator.startScan()
        var snapshots: [ScanProgress] = []
        for await p in stream {
            snapshots.append(p)
            if case .completed = p.state { break }
            if case .failed(let err) = p.state { XCTFail("scan failed: \(err)") }
        }
        return snapshots
    }

    func testInterimScanningSnapshotAndTerminalCompletion() async throws {
        let cats = [
            CategoryDefinition(
                id: "app.cache",
                title: "App Cache",
                paths: [cachesRoot.path],
                riskLevel: .caution
            )
        ]
        let orchestrator = ScanOrchestrator(categoryDefinitions: cats)
        let snapshots = await scanToCompletion(orchestrator)

        let first = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(first.state, .scanning,
                       "first snapshot must be a live .scanning state, not idle")

        // Complaint #1 regression: at least one interim snapshot must carry
        // real-time stats (file count > 0, live current path) so the ring
        // and the stats row move continuously, not only at the end.
        let interimSnapshot = try XCTUnwrap(
            snapshots.first { $0.state == .scanning && $0.stats.fileCount > 0 },
            "interim scanning snapshot with real-time stats required"
        )
        XCTAssertFalse(interimSnapshot.currentNodePath?.isEmpty ?? true,
                       "interim snapshot must carry the currently-scanned file path")
        XCTAssertEqual(interimSnapshot.categoryProgress.count, 1,
                       "interim snapshot must carry the seeded per-category rows")

        let final = try XCTUnwrap(snapshots.last)
        XCTAssertEqual(final.state, .completed)
        let row = try XCTUnwrap(final.categoryProgress.first)
        XCTAssertEqual(row.status, .completed)
        XCTAssertEqual(row.filesFound, 5000)
        XCTAssertEqual(row.totalSize, 1_280_000)
        XCTAssertEqual(final.stats.fileCount, 5000)
        XCTAssertGreaterThan(final.stats.elapsed, 0)
        XCTAssertGreaterThan(final.stats.filesPerSecond, 0)
    }

    func testProgressStreamStartsWithPendingRowsSeeded() async throws {
        let emptyA = a1Root.appendingPathComponent("EmptyA", isDirectory: true)
        let emptyB = a1Root.appendingPathComponent("EmptyB", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: emptyB, withIntermediateDirectories: true)
        let cats = [
            CategoryDefinition(id: "system.cache", title: "System Cache", paths: [emptyA.path], riskLevel: .recommended),
            CategoryDefinition(id: "system.logs", title: "System Logs", paths: [emptyB.path], riskLevel: .recommended),
        ]
        let orchestrator = ScanOrchestrator(categoryDefinitions: cats)
        let snapshots = await scanToCompletion(orchestrator)

        let first = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(first.categoryProgress.count, 2,
                       "first snapshot must seed one pending row per category")
        XCTAssertTrue(first.categoryProgress.allSatisfy { $0.status == .pending })

        let final = try XCTUnwrap(snapshots.last)
        XCTAssertEqual(final.categoryProgress.count, 2)
        XCTAssertTrue(final.categoryProgress.allSatisfy { $0.status == .completed },
                      "terminal snapshot must force-complete every row so the ring reaches 100%")
    }
}

/// Task B1 — pseudo-app splitting. Unmatched top-level folders become their
/// own rows titled with the REAL folder name; files directly in the category
/// root fold into the "其他未识别" sentinel.
@MainActor
final class ScanPseudoAppSplittingTests: XCTestCase {
    private func scanOneCategory(_ categoryRoot: URL) async -> ScanCategory {
        let cats = [
            CategoryDefinition(
                id: "app.cache",
                title: "App Cache",
                paths: [categoryRoot.path],
                riskLevel: .caution
            )
        ]
        let orchestrator = ScanOrchestrator(categoryDefinitions: cats)
        let stream = await orchestrator.startScan()
        var emitted: [ScanCategory] = []
        let consumer = Task { @MainActor in
            for await event in await orchestrator.categoryStream() {
                if case .category(let catEvent) = event {
                    emitted.append(catEvent.category)
                }
            }
        }
        for await p in stream {
            if case .completed = p.state { break }
            if case .failed(let err) = p.state { XCTFail("scan failed: \(err)") }
        }
        await consumer.value
        return try! XCTUnwrap(emitted.first, "scan must emit exactly one category")
    }

    func testUnmatchedTopLevelFolderBecomesPseudoAppRow() async throws {
        let root = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("sclean-b1-pseudo-\(UUID().uuidString)", isDirectory: true)
        let categoryRoot = root.appendingPathComponent("AppCache", isDirectory: true)
        let appDir = categoryRoot.appendingPathComponent("SomeRandomApp", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0xAB, count: 256).write(to: appDir.appendingPathComponent("cache.bin"))

        let category = await scanOneCategory(categoryRoot)
        let sub = try XCTUnwrap(category.subItems.first)
        XCTAssertTrue(sub.isPseudoApp,
                      "unmatched top-level folder must become a pseudo-app row")
        XCTAssertEqual(sub.title, "SomeRandomApp",
                       "pseudo-app row must be titled with the REAL folder name")
        XCTAssertFalse(sub.showAction)
        XCTAssertEqual(sub.directResults.count, 1)
        XCTAssertEqual(sub.riskLevel, .caution)
        XCTAssertFalse(sub.isRecommended,
                       "pseudo-app rows must be off-by-default, never auto-selected")
    }

    func testUnrecognizedRootFilesGoToSentinelSub() async throws {
        let root = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("sclean-b1-sentinel-\(UUID().uuidString)", isDirectory: true)
        let categoryRoot = root.appendingPathComponent("AppCache", isDirectory: true)
        try FileManager.default.createDirectory(at: categoryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0xCD, count: 128).write(to: categoryRoot.appendingPathComponent("stray.bin"))

        let category = await scanOneCategory(categoryRoot)
        let sub = try XCTUnwrap(category.subItems.first)
        XCTAssertEqual(sub.title, "其他未识别")
        XCTAssertEqual(sub.directResults.count, 1)
        XCTAssertFalse(sub.isPseudoApp)
    }
}
