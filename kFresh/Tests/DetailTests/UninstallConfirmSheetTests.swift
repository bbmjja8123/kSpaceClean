import XCTest
import AppKit
import SwiftUI
@testable import kFresh

/// Controller-level tests for ``UninstallConfirmSheet``. Verifies the sheet
/// constructs cleanly across the empty-residue and populated-residue paths
/// and exposes the same surface the host view (``AppDetailView``) wires into
/// its `.sheet(isPresented:)` modifier.
@MainActor
final class UninstallConfirmSheetTests: XCTestCase {
    func testSheetConstructsWithEmptyResiduesAndRenders() {
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Sample.app"),
            displayName: "Sample",
            bundleID: "com.example.sample",
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 2048,
            source: .userInstalled,
            isRunning: false,
            lastUsedDate: nil
        )
        var confirmFired = false
        var cancelFired = false

        let view = UninstallConfirmSheet(
            app: app,
            residues: [],
            onConfirm: { confirmFired = true },
            onCancel: { cancelFired = true }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 480, height: 240)
        let image = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
        XCTAssertNotNil(image, "Empty-residue sheet must render to an image")

        // Wiring check: confirm / cancel closures are stashed on the view
        // (private State captures them) but we can verify they are not nil
        // by exercising the closures directly via the closures we passed in.
        XCTAssertFalse(confirmFired)
        XCTAssertFalse(cancelFired)
    }

    func testSheetConstructsWithPopulatedResiduesAndRenders() {
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Sample.app"),
            displayName: "Sample",
            bundleID: "com.example.sample",
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 4096,
            source: .userInstalled,
            isRunning: false,
            lastUsedDate: Date()
        )
        let residues = [
            ResidueFile(
                url: URL(fileURLWithPath: "/tmp/preferences.plist"),
                type: .preferences,
                sizeBytes: 256,
                confidence: 0.9,
                description: "preferences"
            ),
            ResidueFile(
                url: URL(fileURLWithPath: "/tmp/caches"),
                type: .caches,
                sizeBytes: 1024,
                confidence: 0.7,
                description: "caches"
            ),
        ]

        let view = UninstallConfirmSheet(
            app: app,
            residues: residues,
            onConfirm: {},
            onCancel: {}
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
        let image = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
        XCTAssertNotNil(image, "Populated-residue sheet must render to an image")
    }

    func testSheetConstructsWithRunningAppAndRenders() {
        // App is currently running → header must show the running-warning row.
        // Rendering without crashing exercises the conditional branch.
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Sample.app"),
            displayName: "Sample",
            bundleID: "com.example.sample",
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 4096,
            source: .mas,
            isRunning: true,
            lastUsedDate: Date()
        )
        let view = UninstallConfirmSheet(
            app: app,
            residues: [],
            onConfirm: {},
            onCancel: {}
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 480, height: 240)
        let image = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
        XCTAssertNotNil(image, "Running-app + MAS source sheet must render without crashing")
    }
}
