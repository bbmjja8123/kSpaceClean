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

        // Drive the scan; break on terminal snapshot.
        let stream = await orchestrator.startScan()
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
        // cleared between scans).
        var sawTerminalCompletion = false
        let consumer = Task { @MainActor in
            for await event in await orchestrator.categoryStream() {
                if case .terminal(let p) = event, case .completed = p.state {
                    sawTerminalCompletion = true
                }
            }
        }
        let secondStream = await orchestrator.startScan()
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

        var sawTerminal = false
        let consumer = Task { @MainActor in
            for await event in await orchestrator.categoryStream() {
                if case .terminal = event { sawTerminal = true }
            }
        }
        let stream = await orchestrator.startScan()
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
