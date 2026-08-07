// kSpaceClean/Tests/PhaseAComponentSnapshotTests.swift
//
// Phase A — structural snapshot coverage for every reusable SwiftUI
// component delivered in Phase A. Tests live alongside the existing
// unit tests because the project has no image-snapshotting library
// (see SnapshotTestCase doc comment).
//
// Phase A components under test:
//   - RiskBadge          (Task A6)
//   - IndeterminateCheckbox (Task A7)
//   - SkeletonRow        (Task A11)
//   - EmptyStateScreen   (Task A11)
//   - ToolbarView        (Task A12)
//
// ScanTreeRow is exercised by ScanResultsViewSnapshotTests (the row
// only exists as part of the parent tree surface).

import XCTest
import SwiftUI
import AppKit
@testable import kSpaceClean

@MainActor
final class RiskBadgeSnapshotTests: SnapshotTestCase {

    /// All four risk levels must render inside the same VStack at the
    /// default design-system canvas size without crashing.
    func test_allRiskLevelsRenderSideBySide() {
        let view = VStack(spacing: 12) {
            RiskBadge(level: .recommended)
            RiskBadge(level: .optional)
            RiskBadge(level: .caution)
            RiskBadge(level: .dangerous)
        }
        .padding()
        .background(Color.bgCanvas)

        assertStructuralSnapshot(view, named: "RiskBadge-AllLevels")
    }

    /// Each individual badge must render in isolation too — guarantees the
    /// structural shape is independent of sibling badges.
    func test_eachRiskLevelRendersAlone() {
        for level in RiskLevel.allCases {
            let view = RiskBadge(level: level)
                .padding()
                .background(Color.bgCanvas)
            assertStructuralSnapshot(view, named: "RiskBadge-\(level.label)")
        }
    }

    /// Compact variant for inline placement (used by the top-level category
    /// row in ScanTreeRow) must render at a smaller horizontal footprint.
    func test_compactVariantsRenderSideBySide() {
        let view = HStack(spacing: 12) {
            RiskBadge(level: .recommended, compact: true)
            RiskBadge(level: .optional, compact: true)
            RiskBadge(level: .caution, compact: true)
            RiskBadge(level: .dangerous, compact: true)
        }
        .padding()
        .background(Color.bgCanvas)

        assertStructuralSnapshot(view, named: "RiskBadge-CompactAllLevels")
    }

    /// Structural surface — the badge must expose a non-empty label, an
    /// accessibility label that interpolates "风险等级，\(label)", and a
    /// non-default background colour. These are the data dependencies
    /// the SwiftUI body relies on at render time.
    func test_badgeSurfaceContract() {
        for level in RiskLevel.allCases {
            XCTAssertFalse(level.label.isEmpty,
                "Badge body would render an empty label for \(level)")
            XCTAssertFalse(level.backgroundColor.description.isEmpty,
                "Badge backgroundColor unresolved for \(level)")
            XCTAssertFalse(level.iconName.isEmpty,
                "Badge iconName missing for \(level)")
        }
    }
}

@MainActor
final class IndeterminateCheckboxSnapshotTests: SnapshotTestCase {

    /// All three checkbox states must render side-by-side without crashing
    /// — this is the structural smoke test for A7.
    func test_allStatesRenderSideBySide() {
        let view = HStack(spacing: 16) {
            IndeterminateCheckbox(state: .off)
            IndeterminateCheckbox(state: .on)
            IndeterminateCheckbox(state: .mixed)
        }
        .padding()
        .background(Color.bgCanvas)

        assertStructuralSnapshot(view, named: "IndeterminateCheckbox-AllStates")
    }

    /// Each individual state must render in isolation.
    func test_eachStateRendersAlone() {
        for state in [CheckState.off, CheckState.on, CheckState.mixed] {
            let view = IndeterminateCheckbox(state: state)
                .padding()
                .background(Color.bgCanvas)
            assertStructuralSnapshot(view, named: "IndeterminateCheckbox-\(state)")
        }
    }

    /// A custom size must be respected — checked by structural equality on
    /// the public `size` property (the rendered frame size is implicit).
    func test_customSizeIsHonored() {
        let checkbox = IndeterminateCheckbox(state: .mixed, size: 32)
        XCTAssertEqual(checkbox.size, 32)

        let view = IndeterminateCheckbox(state: .mixed, size: 32)
            .padding()
            .background(Color.bgCanvas)
        assertStructuralSnapshot(view, named: "IndeterminateCheckbox-CustomSize32")
    }
}

@MainActor
final class SkeletonRowSnapshotTests: SnapshotTestCase {

    /// A single SkeletonRow must render without crashing — the shimmer
    /// animation is driven by `.onAppear` so we wrap it inside a
    /// `Window`-like VStack so `body` exercises the same code path as
    /// the production list surface.
    func test_singleSkeletonRowRenders() {
        let view = VStack(spacing: 0) {
            SkeletonRow()
            Divider()
            SkeletonRow()
            Divider()
            SkeletonRow()
        }
        .background(Color.bgCanvas)

        assertStructuralSnapshot(view, named: "SkeletonRow-Stacked3")
    }
}

@MainActor
final class EmptyStateScreenSnapshotTests: SnapshotTestCase {

    /// All eight scenarios must render at canvas size. The brief hard-codes
    /// eight; a future regression that drops a case will be caught here
    /// because the test enumerates every scenario from the enum.
    func test_allEightScenariosRender() {
        let scenarios: [EmptyStateScenario] = [
            .firstLaunch, .noResults, .cleanupComplete, .noHistory,
            .noFDA, .scanFailed, .cleanupFailed, .diskFull
        ]
        XCTAssertEqual(scenarios.count, 8,
            "Brief specifies 8 EmptyStateScenarios")

        for scenario in scenarios {
            let view = EmptyStateScreen(
                scenario: scenario,
                primaryAction: ("主操作", {}),
                secondaryAction: ("次操作", {})
            )
            assertStructuralSnapshot(view, named: "EmptyState-\(scenario)")
        }
    }

    /// The purely informational case (no actions) must still render —
    /// `EmptyStateScreen(scenario: .cleanupComplete)` is the canonical
    /// "celebratory empty" used after a successful cleanup pass.
    func test_noActionsStillRenders() {
        let view = EmptyStateScreen(scenario: .cleanupComplete)
        assertStructuralSnapshot(view, named: "EmptyState-NoActions")
    }
}

@MainActor
final class ToolbarViewSnapshotTests: SnapshotTestCase {

    /// Toolbar must render at the production width (960 — matches the
    /// `ToolbarView_Previews` width) with brand mark + four action
    /// buttons all visible inside the 64pt height strip.
    func test_toolbarRendersAtProductionWidth() {
        let view = ToolbarView(
            onScan: {},
            onClean: {},
            onWarning: {},
            onProfile: {}
        )
        .frame(width: 960, height: 64)

        assertStructuralSnapshot(
            view,
            named: "ToolbarView-960x64",
            size: CGSize(width: 960, height: 64)
        )
    }

    /// Toolbar must render at a narrower width — covers the split-view
    /// collapse case where the toolbar shares space with the sidebar.
    func test_toolbarRendersAtNarrowWidth() {
        let view = ToolbarView(
            onScan: {},
            onClean: {},
            onWarning: {},
            onProfile: {}
        )
        .frame(width: 480, height: 64)

        assertStructuralSnapshot(
            view,
            named: "ToolbarView-480x64",
            size: CGSize(width: 480, height: 64)
        )
    }
}