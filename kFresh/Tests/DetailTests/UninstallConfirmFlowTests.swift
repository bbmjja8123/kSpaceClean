import XCTest
import AppKit
import SwiftUI
@testable import kFresh

/// Placeholder UI test for the uninstall confirm + toast flow.
///
/// The full journey (tap row → tap 卸载 → verify sheet → confirm → verify
/// toast countdown) lands in a later Wave 1 task. Today this bundle has no
/// UI test target — `kFreshTests` is a unit bundle hosted inside `kFresh.app`,
/// so `XCUIApplication().launch()` cannot run without a `targetApplicationPath`
/// in the test configuration. Until a dedicated UI test target exists, this
/// class guards the public surface of the uninstall flow through the
/// controller API: `DetailViewModel.confirmUninstall()` returns an `Optional`
/// matching the contract, and both views can be constructed with sample data
/// without crashing.
final class UninstallConfirmFlowTests: XCTestCase {
    @MainActor
    func testConfirmUninstallReturnsOptionalResult() async {
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Sample.app"),
            displayName: "Sample",
            bundleID: "com.example.sample",
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 1024,
            source: .userInstalled,
            isRunning: false,
            lastUsedDate: nil
        )
        let vm = DetailViewModel(
            app: app,
            residueDetector: ResidueDetector(ruleStore: nil),
            mover: TrashMover(auditLogger: nil, historyRepo: UninstallHistoryRepository(inMemory: true))
        )
        await vm.performSafetyCheck()
        XCTAssertTrue(vm.canUninstall)

        // Protected app short-circuits to nil — guards the gating branch.
        let protected = InstalledApp(
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
        let protectedVM = DetailViewModel(
            app: protected,
            residueDetector: ResidueDetector(ruleStore: nil),
            mover: TrashMover(auditLogger: nil, historyRepo: UninstallHistoryRepository(inMemory: true))
        )
        await protectedVM.performSafetyCheck()
        let blocked = await protectedVM.confirmUninstall()
        XCTAssertNil(blocked, "Protected app must short-circuit to nil")
    }

    @MainActor
    func testConfirmSheetConstructsWithSampleDataWithoutCrashing() {
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Sample.app"),
            displayName: "Sample",
            bundleID: "com.example.sample",
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 4096,
            source: .userInstalled,
            isRunning: true,
            lastUsedDate: Date()
        )
        let residues = [
            ResidueFile(
                url: URL(fileURLWithPath: "/tmp/preferences.plist"),
                type: .preferences,
                sizeBytes: 512,
                confidence: 0.9,
                description: "preferences"
            )
        ]
        let view = UninstallConfirmSheet(
            app: app,
            residues: residues,
            onConfirm: { _ in },
            onCancel: {}
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
        // Render to image — if the view's body throws (missing token, wrong
        // initializer), the bitmap image context request below would crash.
        let image = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
        XCTAssertNotNil(image, "Confirm sheet must render without crashing")
    }

    @MainActor
    func testToastConstructsWithSampleStateWithoutCrashing() {
        let state = UninstallToast.State(
            recordID: UUID(),
            appName: "Sample",
            appSize: 4096
        )
        let view = UninstallToast(state: state, onUndo: {})
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 480, height: 80)
        let image = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
        XCTAssertNotNil(image, "Toast must render without crashing")
    }

    // MARK: - Wave 2 P1 (G-KF-04) freed-bytes readout

    /// Legacy 3-arg init defaults `totalFreedBytes` to `appSize` —
    /// preserves the "app body only" contract that v1.x callers rely on
    /// when they haven't been taught about the residue total.
    func testToastLegacyInitDefaultsTotalFreedToAppSize() {
        let state = UninstallToast.State(
            recordID: UUID(),
            appName: "Sample",
            appSize: 4096
        )
        XCTAssertEqual(state.totalFreedBytes, 4096,
                       "Backward-compat init must default totalFreedBytes to appSize")
    }

    /// Explicit totalFreedBytes (app body + residue sum) is preserved
    /// verbatim — no rounding, no clamping. Drives the post-uninstall
    /// '已释放 X' headline.
    func testToastCarriesExplicitTotalFreedBytes() {
        let state = UninstallToast.State(
            recordID: UUID(),
            appName: "Sample",
            appSize: 4096,
            totalFreedBytes: 4096 + 12_345_678 // app + a fat residue
        )
        XCTAssertEqual(state.totalFreedBytes, 12_349_774)
    }

    /// The new toast with full state must still render (no layout
    /// regression from the split into two lines + the 1.04× bounce).
    func testToastRendersWithExplicitTotalFreed() {
        let state = UninstallToast.State(
            recordID: UUID(),
            appName: "BigResidue",
            appSize: 50_000,
            totalFreedBytes: 2_000_000_000
        )
        let view = UninstallToast(state: state, onUndo: {})
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 480, height: 100)
        let image = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
        XCTAssertNotNil(image, "Toast with totalFreedBytes must render without crashing")
    }
}
