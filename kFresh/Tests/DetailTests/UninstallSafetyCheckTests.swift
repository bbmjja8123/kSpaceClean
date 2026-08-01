import XCTest
import AppKit
@testable import kFresh

/// Covers the `DetailViewModel.confirmUninstall()` API contract: a protected
/// app returns `nil` (so the sheet's confirm button never reaches the
/// `TrashMover`); an unprotected, non-running app drives a real uninstall
/// attempt and yields a `Result` (success or a non-fatal `.trashFailed` from
/// the trash call — both prove the API is reachable).
@MainActor
final class UninstallSafetyCheckTests: XCTestCase {
    /// Protected app (Finder) is gated by `performSafetyCheck` — `canUninstall`
    /// is false, so `confirmUninstall` returns nil without invoking the mover.
    func testProtectedAppCannotReachConfirmSheet() async {
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
            displayName: "Finder",
            bundleID: "com.apple.finder",
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 0,
            source: .appleBuiltIn,
            isRunning: false,
            lastUsedDate: nil
        )
        let vm = DetailViewModel(
            app: app,
            residueDetector: ResidueDetector(ruleStore: nil),
            mover: TrashMover(auditLogger: nil, historyRepo: UninstallHistoryRepository(inMemory: true))
        )
        await vm.performSafetyCheck()
        XCTAssertFalse(vm.canUninstall)
        let outcome = await vm.confirmUninstall()
        XCTAssertNil(outcome, "confirmUninstall must short-circuit nil for protected apps (no mover call)")
        XCTAssertNil(vm.lastUninstallResult, "lastUninstallResult must remain nil when confirmUninstall is blocked")
    }

    /// Non-protected app: confirmUninstall runs the mover. The path
    /// `/Applications/Slack.app` does not exist in the test sandbox, so the
    /// trash call returns a `.failure(.trashFailed(...))`. We only assert
    /// the contract: a `Result` is returned (i.e. not nil) and the published
    /// `lastUninstallResult` mirrors the call.
    func testUnprotectedAppReturnsResultAndMirrorsToLastUninstallResult() async {
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Slack.app"),
            displayName: "Slack",
            bundleID: "com.tinyspeck.chatlyio",
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 512,
            source: .userInstalled,
            isRunning: false,
            lastUsedDate: Date()
        )
        let vm = DetailViewModel(
            app: app,
            residueDetector: ResidueDetector(ruleStore: nil),
            mover: TrashMover(auditLogger: nil, historyRepo: UninstallHistoryRepository(inMemory: true))
        )
        await vm.performSafetyCheck()
        XCTAssertTrue(vm.canUninstall, "Unprotected, non-running app must be uninstallable")
        let outcome = await vm.confirmUninstall()
        XCTAssertNotNil(outcome, "confirmUninstall must return a Result for an unprotected app")
        XCTAssertNotNil(vm.lastUninstallResult, "lastUninstallResult must mirror the most recent confirmUninstall outcome")
    }
}
