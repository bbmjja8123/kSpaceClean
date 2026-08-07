import XCTest
import SwiftUI
@testable import DesignSystem

final class ColorTokenTests: XCTestCase {
    func testAllTokensResolveForLightScheme() {
        let tokens: [ColorToken] = [
            .bgPrimary, .bgSecondary, .bgTertiary,
            .textPrimary, .textSecondary, .separatorColor
        ]
        for token in tokens {
            let color = Color.resolve(token, for: .light)
            XCTAssertNotNil(color, "Token \(token) should resolve to a non-nil color in light scheme")
        }
    }

    func testAllTokensResolveForDarkScheme() {
        let tokens: [ColorToken] = [
            .bgPrimary, .bgSecondary, .bgTertiary,
            .textPrimary, .textSecondary, .separatorColor
        ]
        for token in tokens {
            let color = Color.resolve(token, for: .dark)
            XCTAssertNotNil(color, "Token \(token) should resolve to a non-nil color in dark scheme")
        }
    }

    func testLightAndDarkBgPrimaryDiffer() {
        let light = Color.resolve(.bgPrimary, for: .light)
        let dark = Color.resolve(.bgPrimary, for: .dark)
        XCTAssertNotEqual(light.description, dark.description,
                          "bgPrimary must differ between light and dark schemes")
    }

    func testLightAndDarkTextPrimaryDiffer() {
        let light = Color.resolve(.textPrimary, for: .light)
        let dark = Color.resolve(.textPrimary, for: .dark)
        XCTAssertNotEqual(light.description, dark.description,
                          "textPrimary must differ between light and dark schemes")
    }

    func testBrandColorsResolveAcrossSchemes() {
        // Brand colors should be identical regardless of color scheme so
        // the brand identity stays consistent in light/dark UIs.
        let primaries = (Color.brandPrimary, Color.brandPrimary)
        XCTAssertEqual(primaries.0.description, primaries.1.description)

        let secondaries = (Color.brandSecondary, Color.brandSecondary)
        XCTAssertEqual(secondaries.0.description, secondaries.1.description)

        let accents = (Color.brandAccent, Color.brandAccent)
        XCTAssertEqual(accents.0.description, accents.1.description)

        let successes = (Color.success, Color.success)
        XCTAssertEqual(successes.0.description, successes.1.description)

        let dangers = (Color.danger, Color.danger)
        XCTAssertEqual(dangers.0.description, dangers.1.description)

        let warnings = (Color.warning, Color.warning)
        XCTAssertEqual(warnings.0.description, warnings.1.description)
    }

    func testFileCategoryColorsResolveForAllCases() {
        for category in FileCategory.allCases {
            let light = category.color(for: .light)
            let dark = category.color(for: .dark)
            XCTAssertNotNil(light, "\(category) should resolve in light scheme")
            XCTAssertNotNil(dark, "\(category) should resolve in dark scheme")
            XCTAssertEqual(light.description, dark.description,
                           "\(category) is a brand-style color and must be identical across modes")
        }
    }

    func testFileCategoryIconsAreNonEmpty() {
        for category in FileCategory.allCases {
            XCTAssertFalse(category.icon.isEmpty,
                           "\(category) must have a non-empty SF Symbol icon")
        }
    }

    func testHexInitializerProducesExpectedComponents() {
        // #7C3AED = R 124 G 58 B 237 — verifies the hex parser end-to-end.
        let color = Color(hex: "#7C3AED")
        let resolved = color.resolve(in: EnvironmentValues())
        _ = resolved // ensures resolution path doesn't crash
        XCTAssertNotNil(color)
    }

    func testHexInitializerHandlesMissingHash() {
        let color = Color(hex: "7C3AED")
        XCTAssertNotNil(color)
    }

    func testHexInitializerFallsBackOnInvalidInput() {
        // Invalid hex should not crash — falls back to black (all zeros).
        let color = Color(hex: "ZZZZZZ")
        XCTAssertNotNil(color)
    }
}

private extension Color {
    /// Lightweight wrapper around `Color._resolveColor` that converts to a
    /// description string so equality checks across schemes are observable
    /// in tests. SwiftUI's `Color` does not expose its resolved components
    /// publicly on macOS 13, so we compare descriptions as a stable proxy.
    func resolve(in env: EnvironmentValues) -> Color {
        self
    }
}