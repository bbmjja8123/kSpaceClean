// kWise/Tests/CleanupEngineTests.swift
//
// Task C2 — CleanupEngine tests.
import XCTest
@testable import kWise

final class CleanupEngineTests: XCTestCase {

    // MARK: - Trash-move behaviour

    func testCleanupMovesFileToTrash() async throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        try "test".write(to: tempFile, atomically: true, encoding: .utf8)

        let engine = CleanupEngine(persistence: PersistenceController(inMemory: true))
        let outcome = try await engine.cleanup(targets: [
            CleanupTarget(url: tempFile, size: 4, risk: .recommended)
        ])

        XCTAssertEqual(outcome.succeeded.count, 1)
        XCTAssertTrue(outcome.failed.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path),
                       "Trashed file should no longer be at its original path")
    }

    func testCleanupReturnsFailureForMissingFile() async throws {
        let missing = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString)")
        let engine = CleanupEngine(persistence: PersistenceController(inMemory: true))
        let outcome = try await engine.cleanup(targets: [
            CleanupTarget(url: missing, size: 0, risk: .recommended)
        ])
        XCTAssertTrue(outcome.succeeded.isEmpty)
        XCTAssertEqual(outcome.failed.count, 1)
        XCTAssertEqual(outcome.failed.first?.url, missing)
    }

    // MARK: - History persistence

    func testCleanupWritesHistoryRows() async throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).log")
        try "x".write(to: tempFile, atomically: true, encoding: .utf8)

        let persistence = PersistenceController(inMemory: true)
        let engine = CleanupEngine(persistence: persistence)
        _ = try await engine.cleanup(targets: [
            CleanupTarget(url: tempFile, size: 1, risk: .caution,
                          bundleID: "com.example.app", categoryID: "systemCache")
        ])

        let history = await engine.getHistory()
        XCTAssertEqual(history.count, 1)
        let row = try XCTUnwrap(history.first)
        XCTAssertEqual(row.path, tempFile.path)
        XCTAssertEqual(row.size, 1)
        XCTAssertEqual(row.bundleID, "com.example.app")
        XCTAssertEqual(row.categoryID, "systemCache")
        XCTAssertEqual(row.risk, .caution)
    }

    func testLazyHistoryCleanup() async throws {
        let persistence = PersistenceController(inMemory: true)
        let engine = CleanupEngine(persistence: persistence)

        // Insert an old history row directly.
        let context = persistence.viewContext
        let old = CleanupHistoryItem(context: context)
        old.id = UUID()
        old.path = "/tmp/old"
        old.size = 1024
        old.cleanedAt = Date().addingTimeInterval(-40 * 86_400)  // 40 days ago
        old.riskLevel = "recommended"
        persistence.save(context: context)

        await engine.cleanupStaleHistory(olderThan: 30)

        let history = await engine.getHistory()
        XCTAssertEqual(history.count, 0)
    }

    func testEmptyTargetsReturnsEmptyOutcomeWithoutWritingHistory() async throws {
        let persistence = PersistenceController(inMemory: true)
        let engine = CleanupEngine(persistence: persistence)

        let outcome = try await engine.cleanup(targets: [])
        XCTAssertTrue(outcome.isFullySuccessful)
        XCTAssertEqual(outcome.successCount, 0)
        let historyCount = await engine.getHistory().count
        XCTAssertEqual(historyCount, 0)
    }

    // MARK: - Streaming API preserved

    func testStreamingCleanupEmitsCompletedForAllSuccesses() async throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        try "y".write(to: tempFile, atomically: true, encoding: .utf8)

        let engine = CleanupEngine(persistence: PersistenceController(inMemory: true))
        var finalState: CleanupProgress.State?
        for await progress in engine.cleanup(urls: [tempFile], warnHandling: .skip) {
            if progress.state == .completed || progress.state == .failed {
                finalState = progress.state
            }
        }
        XCTAssertEqual(finalState, .completed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path))
    }
}