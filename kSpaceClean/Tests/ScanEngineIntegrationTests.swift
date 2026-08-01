// kSpaceClean/Tests/ScanEngineIntegrationTests.swift
//
// E2E integration test for the `ScanEngine` MainActor wrapper (the object
// `ScanResultsViewModel` talks to).
//
// These tests pin the *deterministic* bug from the 2026-07-31 build:
// `ScanResultsViewModel.startRealScan` called `engine.startScan()` (which
// is fire-and-forget — it returns as soon as the orchestrator's stream is
// created) and then immediately read `engine.categories`, which was still
// empty. The user saw "干净 / 没有可清理项目" instantly even though the
// real scan was still walking the filesystem with no observer.
//
// The fix is `waitForScanCompletion()`, which awaits the scan task that
// drains the orchestrator's streams into the `@Published` state. These
// tests drive the real orchestrator + FileEnumerator against an on-disk
// fixture and assert that `waitForScanCompletion()` really does return
// with the category tree populated and the progress terminal.
//
// The second test pins the re-entrancy hardening (`scanGeneration`):
// reusing the same engine for a second scan must not inherit stale state
// from the first run's in-flight unstructured tasks.
import XCTest
import FileScanner
@testable import kSpaceClean

@MainActor
final class ScanEngineIntegrationTests: XCTestCase {

    /// Top-level fixture root. Resolved once per test invocation.
    private var fixtureRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        let root = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("sclean-fixture-engine-\(UUID().uuidString)",
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

    /// A single-category orchestrator whose worker walks the fixture's
    /// Caches subtree. Shared by both tests.
    private func makeEngine() -> ScanEngine {
        let cats = [
            CategoryDefinition(
                id: "fixture.cache",
                title: "Fixture Cache",
                paths: [fixtureRoot.appendingPathComponent("Caches").path],
                riskLevel: .recommended
            )
        ]
        return ScanEngine(orchestrator: ScanOrchestrator(categoryDefinitions: cats))
    }

    // MARK: - Bug 1 fix: waitForScanCompletion returns the real results

    func testWaitForScanCompletionReturnsFinalCategories() async throws {
        let engine = makeEngine()

        // startScan() is fire-and-forget; the caller must await
        // waitForScanCompletion() before reading categories/progress.
        await engine.startScan()
        await engine.waitForScanCompletion()

        XCTAssertEqual(engine.categories.map(\.categoryID), ["fixture.cache"],
                       "waitForScanCompletion must leave the category tree populated")
        let category = try XCTUnwrap(engine.categories.first)
        XCTAssertGreaterThan(category.totalSize, 0,
                             "the 256-byte fixture file must round-trip through the pipeline")
        guard case .completed = engine.progress.state else {
            return XCTFail("scan must end in .completed, got \(engine.progress.state)")
        }
    }

    // MARK: - Re-entrancy fix: a second scan on the same engine starts clean

    func testSecondScanOnSameEngineStartsClean() async throws {
        let engine = makeEngine()

        // First scan: complete and observe the category.
        await engine.startScan()
        await engine.waitForScanCompletion()
        let firstIDs = engine.categories.map(\.categoryID)
        XCTAssertEqual(firstIDs, ["fixture.cache"])
        guard case .completed = engine.progress.state else {
            return XCTFail("first scan must end in .completed, got \(engine.progress.state)")
        }

        // Second scan on the SAME engine: stale unstructured tasks from
        // the first run (which cancellation cannot reach) must not ingest
        // into the freshly-reset state. The scanGeneration guard drops
        // them, so the second run must re-emit exactly its own category.
        await engine.startScan()
        await engine.waitForScanCompletion()

        XCTAssertEqual(engine.categories.map(\.categoryID), ["fixture.cache"],
                       "second scan must re-emit its category from a clean slate")
        guard case .completed = engine.progress.state else {
            return XCTFail("second scan must end in .completed, got \(engine.progress.state)")
        }
    }
}
