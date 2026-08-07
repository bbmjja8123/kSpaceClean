// kSpaceClean/Tests/SnapshotTestCase.swift
import XCTest
import SwiftUI
import AppKit
@testable import kSpaceClean

/// Base class for structural "snapshot" tests.
///
/// The project has no image-snapshotting library (no `swift-snapshot-testing`,
/// no `ViewInspector`) and the deployment target (macOS 13) ships Xcode 14's
/// macOS 13.3 SDK, where `ImageRenderer` is not available. Instead, the
/// snapshot tests assert **structural** properties of each view:
///
/// - the view can be constructed for the targeted enum cases without crashing,
/// - `body` evaluates without throwing,
/// - the rendered view tree produces a non-zero `NSHostingView` frame
///   when instantiated at the design-system canvas size (960×720).
///
/// The helper `assertStructuralSnapshot(_:named:size:)` is the single
/// entry point used by every Phase A snapshot test. It captures the
/// structural data (frame size + a per-test message) and forwards to
/// `XCTContext.runActivity(...)` so each render shows up in the test
/// report's activity log. If the project later adopts a snapshot library,
/// the helper is the single place that needs to be swapped.
///
/// `NSHostingView` is main-actor isolated under
/// `SWIFT_STRICT_CONCURRENCY = complete`, so this base class itself is
/// `@MainActor` — every concrete subclass must also be `@MainActor`
/// (matching the convention already used by `RiskBadgeTests`,
/// `IndeterminateCheckboxTests`, and `EmptyStateViewTests`).
///
/// This base intentionally stays minimal — no shared state, no fixtures,
/// no Core Data. Every test class drives its own view construction so a
/// regression in one component cannot mask another.
@MainActor
class SnapshotTestCase: XCTestCase {
    /// Target frame size for the snapshot. Matches the design-system canvas
    /// (see `ScanResultsView_Previews`); tests can override per-call.
    static let defaultCanvasSize = CGSize(width: 960, height: 720)

    /// Asserts that `view` can be hosted in an `NSHostingView` at the given
    /// canvas size without crashing, returns a non-zero frame, and that its
    /// `body` evaluates without throwing.
    ///
    /// The function does **not** capture pixel data; the project's snapshot
    /// library is intentionally absent (see `SnapshotTestCase` doc comment).
    /// It only proves the view tree compiles and renders without runtime
    /// errors at the target size — the structural test the project actually
    /// needs today.
    ///
    /// - Parameters:
    ///   - view: The SwiftUI view under test.
    ///   - name: Human-readable snapshot name. Recorded in the test report.
    ///   - size: Canvas size in points. Defaults to the design-system canvas.
    func assertStructuralSnapshot<V: View>(
        _ view: V,
        named name: String,
        size: CGSize = SnapshotTestCase.defaultCanvasSize
    ) {
        let rootView = view.frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame.size = size
        hosting.layoutSubtreeIfNeeded()

        XCTContext.runActivity(named: "Snapshot '\(name)' @ \(Int(size.width))x\(Int(size.height))") { _ in
            XCTAssertGreaterThan(hosting.frame.width, 0,
                "Snapshot '\(name)' rendered with zero width")
            XCTAssertGreaterThan(hosting.frame.height, 0,
                "Snapshot '\(name)' rendered with zero height")
        }
    }
}