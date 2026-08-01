import XCTest
import AppKit
@testable import kFresh

@MainActor
final class DetailViewModelTests: XCTestCase {
    /// Builds an uninstallable test app. `isProtected` / `protectionReason`
    /// are computed, not init params — use `com.apple.dock` (in the protected
    /// allowlist) when a protected app is needed.
    func makeApp(running: Bool = false) -> InstalledApp {
        InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Test.app"),
            displayName: "Test",
            bundleID: "com.example.test",
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 1024,
            source: .userInstalled,
            isRunning: running,
            lastUsedDate: Date()
        )
    }

    func testProtectedAppBlocksUninstall() async {
        // com.apple.dock is in the `isBundleIDProtected` allowlist, so
        // `isProtected` is computed true and `protectionReason` is the
        // system-component copy.
        let protected = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Dock.app"),
            displayName: "Dock",
            bundleID: "com.apple.dock",
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 1024,
            source: .appleBuiltIn
        )
        let vm = DetailViewModel(
            app: protected,
            residueDetector: ResidueDetector(ruleStore: nil),
            mover: TrashMover(auditLogger: nil, historyRepo: UninstallHistoryRepository(inMemory: true))
        )
        await vm.performSafetyCheck()
        XCTAssertFalse(vm.canUninstall)
        if case .blocked(let reason) = vm.safetyCheck {
            XCTAssertTrue(reason.contains("系统"))
        } else {
            XCTFail("Expected blocked state")
        }
    }

    func testRunningAppAllowsUninstallAfterAcknowledgment() async {
        let vm = DetailViewModel(
            app: makeApp(running: true),
            residueDetector: ResidueDetector(ruleStore: nil),
            mover: TrashMover(auditLogger: nil, historyRepo: UninstallHistoryRepository(inMemory: true))
        )
        await vm.performSafetyCheck()
        // Running app still passes; the sheet surfaces the running warning
        XCTAssertTrue(vm.canUninstall)
        XCTAssertEqual(vm.safetyCheck, .passed)
    }

    func testResiduesSortedByConfidenceDescending() async {
        let vm = DetailViewModel(
            app: makeApp(),
            residueDetector: ResidueDetector(ruleStore: nil),
            mover: TrashMover(auditLogger: nil, historyRepo: UninstallHistoryRepository(inMemory: true))
        )
        vm.residues = [
            ResidueFile(url: URL(fileURLWithPath: "/tmp/a"), type: .preferences, sizeBytes: 100, confidence: 0.5, description: "low"),
            ResidueFile(url: URL(fileURLWithPath: "/tmp/b"), type: .caches, sizeBytes: 200, confidence: 0.9, description: "high"),
        ]
        XCTAssertEqual(vm.residues.first?.confidence, 0.9)
    }
}
