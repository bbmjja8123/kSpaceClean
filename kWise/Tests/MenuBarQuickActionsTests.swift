// kWise/Tests/MenuBarQuickActionsTests.swift
//
// v2.0 Phase 3 — the menu bar's quick actions were empty stubs and the
// "最近清理" row was hardcoded fake data. These tests pin the real
// behaviour: actions route through installed closures, and the summary row
// updates from CleanupEventSink events only.
import XCTest
@testable import kWise

@MainActor
final class MenuBarQuickActionsTests: XCTestCase {

    func testQuickCleanInvokesInstalledClosure() {
        let manager = MenuBarManager()
        var called = false
        manager.onQuickClean = { called = true }
        manager.perform(NSSelectorFromString("quickClean"))
        XCTAssertTrue(called, "quickClean must route to the installed closure")
    }

    func testQuickScanInvokesInstalledClosure() {
        let manager = MenuBarManager()
        var called = false
        manager.onQuickScan = { called = true }
        manager.perform(NSSelectorFromString("quickScan"))
        XCTAssertTrue(called)
    }

    func testOpenSettingsInvokesInstalledClosure() {
        let manager = MenuBarManager()
        var called = false
        manager.onOpenSettings = { called = true }
        manager.perform(NSSelectorFromString("openSettings"))
        XCTAssertTrue(called)
    }

    func testLastCleanupSummaryStartsHonest() {
        let manager = MenuBarManager()
        XCTAssertNotEqual(manager.lastCleanupSummary, "最近清理: 今天 10:30 · 3.2 GB",
                          "The old hardcoded fake string must never come back")
    }

    func testSinkEventUpdatesLastCleanupSummary() async {
        let manager = MenuBarManager()
        await manager.cleanupDidFinish(
            CleanupEvent(freedBytes: 3_200_000_000, measuredBytes: nil, itemCount: 12)
        )
        XCTAssertTrue(manager.lastCleanupSummary.contains("GB"),
                      "Summary must reflect the real freed bytes")
    }

    func testSinkIgnoresEmptyRuns() async {
        let manager = MenuBarManager()
        await manager.cleanupDidFinish(
            CleanupEvent(freedBytes: 0, measuredBytes: nil, itemCount: 0)
        )
        // Zero-byte runs shouldn't overwrite the honest "暂无" state with noise.
        XCTAssertNotEqual(manager.lastCleanupSummary, "0 B")
    }
}
