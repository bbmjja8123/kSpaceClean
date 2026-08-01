import AppKit
import SwiftUI
import XCTest
@testable import kFresh

/// Controller-level tests for ``ProGateModifier``: lock-state transitions and
/// a smoke render of the gated content (mirrors ``UninstallConfirmSheetTests``).
@MainActor
final class ProGateModifierTests: XCTestCase {
    override func tearDown() async throws {
        // Reset the shared override key so it cannot leak into other tests.
        UserDefaults.standard.set(false, forKey: StoreManager.testOverrideKey)
    }

    func testModifierIsLockedWhenFree() {
        let manager = StoreManager()
        let modifier = ProGateModifier(store: manager)
        XCTAssertTrue(modifier.isLocked)
    }

    func testModifierUnlocksWhenPro() {
        let manager = StoreManager()
        manager.setProForTesting(true)
        let modifier = ProGateModifier(store: manager)
        XCTAssertFalse(modifier.isLocked)
    }

    func testGatedContentRenders() {
        let manager = StoreManager()
        let view = Text("深度清理")
            .proGate(store: manager)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 200)
        let image = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
        XCTAssertNotNil(image, "Gated content must render to an image")
    }
}
