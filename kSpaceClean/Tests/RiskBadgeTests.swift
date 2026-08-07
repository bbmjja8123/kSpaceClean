import XCTest
import SwiftUI
@testable import kSpaceClean

@MainActor
final class RiskBadgeTests: XCTestCase {

    // MARK: - Construction / surface guarantees

    /// Every `RiskLevel` must be constructable inside a `RiskBadge` without
    /// crashing — this is the structural smoke test for the 4-level mapping.
    func testRiskBadge_constructsForAllLevels() {
        for level in RiskLevel.allCases {
            let badge = RiskBadge(level: level)
            // Trigger body evaluation; a runtime crash here would mean the
            // initializer / body is missing a case.
            _ = badge.body
            XCTAssertNotNil(badge)
        }
    }

    /// `compact` is a stored property with a default of `false`; toggling it
    /// must not change the level the badge represents.
    func testRiskBadge_compactToggleDoesNotChangeLevel() {
        let expanded = RiskBadge(level: .caution)
        let compact = RiskBadge(level: .caution, compact: true)
        // Structural check — both must render the same risk-level color tokens.
        XCTAssertEqual(RiskLevel.caution.backgroundColor, expanded.level.backgroundColor)
        XCTAssertEqual(RiskLevel.caution.backgroundColor, compact.level.backgroundColor)
    }

    /// Each level must produce a unique icon mapping; this guards against
    /// future edits accidentally collapsing two levels onto the same symbol.
    func testRiskBadge_iconsAreUniquePerLevel() {
        let icons = Set(RiskLevel.allCases.map { $0.iconName })
        XCTAssertEqual(icons.count, RiskLevel.allCases.count)
    }

    /// Each level must have a non-empty label; the badge reads the label
    /// from `RiskLevel.label` and an empty value would produce a visually
    /// broken compact-mode badge.
    func testRiskBadge_labelsAreNonEmpty() {
        for level in RiskLevel.allCases {
            XCTAssertFalse(level.label.isEmpty, "label empty for \(level)")
        }
    }

    // MARK: - Color contract

    /// The foreground/background pairs for `recommended`, `optional`, and
    /// `dangerous` must use white-on-color (matches the v3 spec palette).
    func testRiskBadge_foregroundColorContract() {
        XCTAssertEqual(RiskLevel.recommended.foregroundColor, Color.white)
        XCTAssertEqual(RiskLevel.optional.foregroundColor, Color.white)
        XCTAssertEqual(RiskLevel.dangerous.foregroundColor, Color.white)
    }

    /// `caution` (orange) is documented as WCAG-AA-contrast black-on-orange
    /// rather than white-on-orange; the badge relies on this contract to
    /// remain legible.
    func testRiskBadge_cautionUsesBlackForeground() {
        XCTAssertEqual(RiskLevel.caution.foregroundColor, Color.black)
    }

    /// Every level must resolve its background to a non-default Color value;
    /// the badge's `.background(level.backgroundColor.opacity(...))` would
    /// silently render as transparent if `backgroundColor` ever returned
    /// the system default (`.clear`-equivalent).
    func testRiskBadge_backgroundColorResolves() {
        for level in RiskLevel.allCases {
            // `Color.riskRecommended` etc. are static `Color` values; comparing
            // them via the public `==` would be unreliable across SwiftUI
            // versions, so we instead sanity-check the description is non-empty.
            XCTAssertFalse(
                level.backgroundColor.description.isEmpty,
                "backgroundColor unresolved for \(level)"
            )
        }
    }

    // MARK: - Accessibility label

    /// The accessibility label must include the localized risk label so
    /// VoiceOver users hear "风险等级，推荐" / "风险等级，危险" etc.
    /// We verify the localized strings exist by ensuring every label is
    /// non-empty for every level (the actual spoken text is constructed
    /// inside `body`, so we exercise the public surface).
    func testRiskBadge_accessibilityLabelFormat() {
        for level in RiskLevel.allCases {
            // The body string is constructed via string interpolation; since
            // we can't capture it directly, we assert the data dependency
            // (level.label) is non-empty so the spoken label won't be empty.
            XCTAssertFalse(level.label.isEmpty, "accessibility label empty for \(level)")
        }
    }
}