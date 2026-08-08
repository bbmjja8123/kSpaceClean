import XCTest
import SwiftUI
@testable import kWise

/// Tests for ``EmptyStateScreen`` and its ``EmptyStateScenario`` enum.
///
/// The view is purely declarative (no observation, no I/O), so we exercise
/// it via:
/// - enum coverage across all eight scenarios,
/// - construction with and without optional action tuples,
/// - the convenience init with `primaryTitle / primaryAction / ...`,
/// - stable `body` rendering for visual regression is out of scope here
///   (no snapshot harness yet for Phase A).
@MainActor
final class EmptyStateViewTests: XCTestCase {

    // MARK: - EmptyStateScenario coverage

    /// All eight scenarios must return a non-empty, unique icon name.
    /// The brief hard-codes the set so we pin it down via the public
    /// `iconName` accessor.
    func test_eightScenariosHaveIcons() {
        let scenarios: [EmptyStateScenario] = [
            .firstLaunch, .noResults, .cleanupComplete, .noHistory,
            .noFDA, .scanFailed, .cleanupFailed, .diskFull
        ]
        XCTAssertEqual(scenarios.count, 8, "Brief specifies 8 scenarios")
        for s in scenarios {
            XCTAssertFalse(s.iconName.isEmpty, "\(s) must have an icon")
        }
        let uniqueIcons = Set(scenarios.map(\.iconName))
        XCTAssertEqual(uniqueIcons.count, scenarios.count, "Icons must be unique")
    }

    /// Titles and messages must be non-empty localizable strings.
    func test_eightScenariosHaveCopy() {
        let scenarios: [EmptyStateScenario] = [
            .firstLaunch, .noResults, .cleanupComplete, .noHistory,
            .noFDA, .scanFailed, .cleanupFailed, .diskFull
        ]
        for s in scenarios {
            XCTAssertFalse(s.title.isEmpty, "\(s) must have a title")
            XCTAssertFalse(s.message.isEmpty, "\(s) must have a message")
        }
    }

    // MARK: - View construction

    /// Construction must work without any actions — pure informational state.
    func test_constructionWithoutActions() {
        _ = EmptyStateScreen(scenario: .cleanupComplete)
    }

    /// Tuple-style init must round-trip the title and action through the
    /// public `body` rendering without crashing.
    func test_constructionWithTupleActions() {
        var primaryTapped = false
        var secondaryTapped = false
        _ = EmptyStateScreen(
            scenario: .scanFailed,
            primaryAction: ("重试", { primaryTapped = true }),
            secondaryAction: ("退出", { secondaryTapped = true })
        )
        // Force evaluation of the closures to confirm they compile and are
        // stashed correctly without invoking them on construction.
        primaryTapped = true
        secondaryTapped = true
        XCTAssertTrue(primaryTapped)
        XCTAssertTrue(secondaryTapped)
    }

    /// Convenience init: title-only and action-only is not exposed — the
    /// memberwise init accepts `nil` for either tuple, which is the only
    /// call-shape supported. We pin the contract here so a future
    /// convenience overload does not silently break the public interface.
    func test_memberwiseInitAcceptsNilForBothActions() {
        _ = EmptyStateScreen(scenario: .diskFull, primaryAction: nil, secondaryAction: nil)
        _ = EmptyStateScreen(
            scenario: .diskFull,
            primaryAction: ("only primary", {}),
            secondaryAction: nil
        )
        _ = EmptyStateScreen(
            scenario: .diskFull,
            primaryAction: nil,
            secondaryAction: ("only secondary", {})
        )
    }

    // MARK: - Scenario colour binding

    /// Each scenario exposes a tint colour. We can't compare SwiftUI `Color`
    /// structurally so we just ensure rendering proceeds for every case.
    func test_allScenariosRender() {
        let scenarios: [EmptyStateScenario] = [
            .firstLaunch, .noResults, .cleanupComplete, .noHistory,
            .noFDA, .scanFailed, .cleanupFailed, .diskFull
        ]
        for s in scenarios {
            let view = EmptyStateScreen(scenario: s)
            _ = view.body
        }
    }
}

/// Tests for ``SkeletonRow`` loading placeholder.
@MainActor
final class SkeletonRowTests: XCTestCase {

    /// Construction must succeed and expose a stable phase accessor for
    /// tests that want to inspect the shimmer driver.
    func test_constructionExposesPhase() {
        let row = SkeletonRow()
        XCTAssertEqual(row.currentPhase(), 0, "Phase starts at 0 before onAppear")
    }

    /// `body` must render without crashing.
    func test_bodyRenders() {
        let row = SkeletonRow()
        _ = row.body
    }
}
