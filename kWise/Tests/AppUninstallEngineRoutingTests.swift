// kWise/Tests/AppUninstallEngineRoutingTests.swift
//
// v2.0 Phase 2 — tool modules route through CleanupEngine (history, quota,
// sinks) instead of raw trashItem. Verified at the VM level with an
// in-memory engine.
import XCTest
@testable import kWise

@MainActor
final class AppUninstallEngineRoutingTests: XCTestCase {

    func testUninstallSelectedUsesEngineAndRecordsHistory() async throws {
        // Fake "app": a directory pretending to be a bundle + a leftover.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("uninstall-test-\(UUID().uuidString)", isDirectory: true)
        let appDir = root.appendingPathComponent("Fake.app", isDirectory: true)
        let leftover = root.appendingPathComponent("leftover.txt")
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        try Data([0x1]).write(to: appDir.appendingPathComponent("exec"))
        try Data("x".utf8).write(to: leftover)
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = CleanupEngine(persistence: PersistenceController(inMemory: true))
        let vm = AppUninstallViewModel(engine: engine)

        // Seed an entry the way the scanner would.
        vm.entries = [
            UninstallAppEntry(
                appName: "Fake",
                bundleID: "test.fake.app",
                appURL: appDir,
                appSize: 1,
                leftoverURLs: [leftover],
                leftoverSize: 1,
                lastUsedDate: nil, installDate: nil, isRunning: false,
                source: .userInstalled, residues: []
            )
        ]

        let result = await vm.uninstallSelected()
        XCTAssertEqual(result.succeeded, ["Fake"])
        XCTAssertTrue(result.failed.isEmpty)

        // Engine routing: both the bundle and the leftover are in history.
        let history = await engine.getHistory()
        let paths = Set(history.map(\.path))
        XCTAssertTrue(paths.contains(appDir.path), "App bundle must appear in restorable history")
        XCTAssertTrue(paths.contains(leftover.path), "Leftover must appear in restorable history")
        for row in history {
            XCTAssertEqual(row.risk, .caution, "App uninstall is a caution-risk action")
        }
    }

    func testQuotaExhaustionSurfacesCallback() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("uninstall-quota-\(UUID().uuidString)", isDirectory: true)
        let appDir = root.appendingPathComponent("Fake2.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        try Data(count: 1_000).write(to: appDir.appendingPathComponent("big"))
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = CleanupEngine(
            persistence: PersistenceController(inMemory: true),
            quota: StubQuota(remaining: 10)  // Too small for the 1 KB app.
        )
        let vm = AppUninstallViewModel(engine: engine)
        var quotaSignalled = false
        vm.onQuotaExhausted = { quotaSignalled = true }

        vm.entries = [
            UninstallAppEntry(
                appName: "Fake2",
                bundleID: "test.fake2.app",
                appURL: appDir,
                appSize: 1_000,
                leftoverURLs: [],
                leftoverSize: 0,
                lastUsedDate: nil, installDate: nil, isRunning: false,
                source: .userInstalled, residues: []
            )
        ]

        let result = await vm.uninstallSelected()
        XCTAssertEqual(result.failed, ["Fake2"], "Nothing cleaned → uninstall reported as failed")
        XCTAssertTrue(quotaSignalled, "Quota exhaustion must reach the paywall callback")
        XCTAssertFalse(FileManager.default.fileExists(atPath: appDir.path) == false,
                       "App must still exist when quota blocked the cleanup")
    }
}
