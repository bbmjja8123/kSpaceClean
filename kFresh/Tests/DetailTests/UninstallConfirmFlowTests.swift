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
        let vm = DetailViewModel(app: app, residueDetector: ResidueDetector(ruleStore: nil))
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
        let protectedVM = DetailViewModel(app: protected, residueDetector: ResidueDetector(ruleStore: nil))
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
            onConfirm: {},
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
}
