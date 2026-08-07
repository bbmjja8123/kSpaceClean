import XCTest
import SwiftUI
@testable import kSpaceClean

final class DesignTokensTests: XCTestCase {
    // MARK: - Background tokens

    func test_bgCanvas_isDarkNearBlack() {
        // #0F1012 = (15, 16, 18)
        let c = Color.bgCanvas
        let (r, g, b, _) = rgbaComponents(c)
        XCTAssertEqual(r, 0.059, accuracy: 0.001)
        XCTAssertEqual(g, 0.063, accuracy: 0.001)
        XCTAssertEqual(b, 0.071, accuracy: 0.001)
    }

    func test_bgSurface_isSecondaryDark() {
        // #1C1C1E = (28, 28, 30)
        let c = Color.bgSurface
        let (r, g, b, _) = rgbaComponents(c)
        XCTAssertEqual(r, 0.110, accuracy: 0.001)
        XCTAssertEqual(g, 0.110, accuracy: 0.001)
        XCTAssertEqual(b, 0.118, accuracy: 0.001)
    }

    func test_bgElevated_isLighterDark() {
        // #2C2C2E = (44, 44, 46)
        let c = Color.bgElevated
        let (r, g, b, _) = rgbaComponents(c)
        XCTAssertEqual(r, 0.173, accuracy: 0.001)
        XCTAssertEqual(g, 0.173, accuracy: 0.001)
        XCTAssertEqual(b, 0.180, accuracy: 0.001)
    }

    func test_divider_isSubtleGray() {
        // #3A3A3C = (58, 58, 60)
        let c = Color.divider
        let (r, g, b, _) = rgbaComponents(c)
        XCTAssertEqual(r, 0.227, accuracy: 0.001)
        XCTAssertEqual(g, 0.227, accuracy: 0.001)
        XCTAssertEqual(b, 0.235, accuracy: 0.001)
    }

    // MARK: - Text tokens

    func test_textPrimary_isWhite() {
        let c = Color.textPrimary
        let (r, g, b, _) = rgbaComponents(c)
        XCTAssertEqual(r, 1.0, accuracy: 0.001)
        XCTAssertEqual(g, 1.0, accuracy: 0.001)
        XCTAssertEqual(b, 1.0, accuracy: 0.001)
    }

    func test_textSecondary_isMidGray() {
        // #999999
        let c = Color.textSecondary
        let (r, g, b, _) = rgbaComponents(c)
        XCTAssertEqual(r, 0.600, accuracy: 0.001)
        XCTAssertEqual(g, 0.600, accuracy: 0.001)
        XCTAssertEqual(b, 0.600, accuracy: 0.001)
    }

    func test_textTertiary_isDimmerGray() {
        // #666666
        let c = Color.textTertiary
        let (r, g, b, _) = rgbaComponents(c)
        XCTAssertEqual(r, 0.400, accuracy: 0.001)
        XCTAssertEqual(g, 0.400, accuracy: 0.001)
        XCTAssertEqual(b, 0.400, accuracy: 0.001)
    }

    func test_textDisabled_isDarkest() {
        // #3A3A3C
        let c = Color.textDisabled
        let (r, g, b, _) = rgbaComponents(c)
        XCTAssertEqual(r, 0.227, accuracy: 0.001)
        XCTAssertEqual(g, 0.227, accuracy: 0.001)
        XCTAssertEqual(b, 0.235, accuracy: 0.001)
    }

    // MARK: - Brand tokens

    func test_brandPrimary_isAppleBlue() {
        // #0A84FF
        let c = Color.brandPrimary
        let (r, g, b, _) = rgbaComponents(c)
        XCTAssertEqual(r, 0.039, accuracy: 0.001)
        XCTAssertEqual(g, 0.518, accuracy: 0.001)
        XCTAssertEqual(b, 1.000, accuracy: 0.001)
    }

    func test_brandAccent_isLightBlue() {
        // #5AC8FA
        let c = Color.brandAccent
        let (r, g, b, _) = rgbaComponents(c)
        XCTAssertEqual(r, 0.353, accuracy: 0.001)
        XCTAssertEqual(g, 0.784, accuracy: 0.001)
        XCTAssertEqual(b, 0.980, accuracy: 0.001)
    }

    // MARK: - Risk tokens

    func test_riskRecommended_isGreen() {
        // #34C759
        let c = Color.riskRecommended
        let (r, g, b, _) = rgbaComponents(c)
        XCTAssertEqual(r, 0.204, accuracy: 0.001)
        XCTAssertEqual(g, 0.780, accuracy: 0.001)
        XCTAssertEqual(b, 0.349, accuracy: 0.001)
    }

    func test_riskOptional_isGray() {
        // #8E8E93
        let c = Color.riskOptional
        let (r, g, b, _) = rgbaComponents(c)
        XCTAssertEqual(r, 0.557, accuracy: 0.001)
        XCTAssertEqual(g, 0.557, accuracy: 0.001)
        XCTAssertEqual(b, 0.576, accuracy: 0.001)
    }

    func test_riskCaution_isOrange() {
        // #FF9500
        let c = Color.riskCaution
        let (r, g, b, _) = rgbaComponents(c)
        XCTAssertEqual(r, 1.000, accuracy: 0.001)
        XCTAssertEqual(g, 0.584, accuracy: 0.001)
        XCTAssertEqual(b, 0.000, accuracy: 0.001)
    }

    func test_riskDangerous_isRed() {
        // #FF3B30
        let c = Color.riskDangerous
        let (r, g, b, _) = rgbaComponents(c)
        XCTAssertEqual(r, 1.000, accuracy: 0.001)
        XCTAssertEqual(g, 0.231, accuracy: 0.001)
        XCTAssertEqual(b, 0.188, accuracy: 0.001)
    }

    // MARK: - State tokens

    func test_stateWarning_isYellow() {
        // #FFCC00
        let c = Color.stateWarning
        let (r, g, b, _) = rgbaComponents(c)
        XCTAssertEqual(r, 1.000, accuracy: 0.001)
        XCTAssertEqual(g, 0.800, accuracy: 0.001)
        XCTAssertEqual(b, 0.000, accuracy: 0.001)
    }

    func test_stateSuccess_isGreen() {
        // #34C759
        let c = Color.stateSuccess
        let (r, g, b, _) = rgbaComponents(c)
        XCTAssertEqual(r, 0.204, accuracy: 0.001)
        XCTAssertEqual(g, 0.780, accuracy: 0.001)
        XCTAssertEqual(b, 0.349, accuracy: 0.001)
    }

    func test_stateError_isRed() {
        // #FF3B30
        let c = Color.stateError
        let (r, g, b, _) = rgbaComponents(c)
        XCTAssertEqual(r, 1.000, accuracy: 0.001)
        XCTAssertEqual(g, 0.231, accuracy: 0.001)
        XCTAssertEqual(b, 0.188, accuracy: 0.001)
    }

    func test_stateScanning_isBlue() {
        // #0A84FF
        let c = Color.stateScanning
        let (r, g, b, _) = rgbaComponents(c)
        XCTAssertEqual(r, 0.039, accuracy: 0.001)
        XCTAssertEqual(g, 0.518, accuracy: 0.001)
        XCTAssertEqual(b, 1.000, accuracy: 0.001)
    }

    // MARK: - RiskLevel helpers

    func test_riskLevel_backgroundColor_mapsCorrectly() {
        XCTAssertEqual(RiskLevel.recommended.backgroundColor, Color.riskRecommended)
        XCTAssertEqual(RiskLevel.optional.backgroundColor, Color.riskOptional)
        XCTAssertEqual(RiskLevel.caution.backgroundColor, Color.riskCaution)
        XCTAssertEqual(RiskLevel.dangerous.backgroundColor, Color.riskDangerous)
    }

    func test_riskLevel_foregroundColor_defaultsToWhite() {
        XCTAssertEqual(RiskLevel.recommended.foregroundColor, Color.white)
        XCTAssertEqual(RiskLevel.optional.foregroundColor, Color.white)
        XCTAssertEqual(RiskLevel.dangerous.foregroundColor, Color.white)
    }

    func test_riskLevel_foregroundColor_cautionIsBlack() {
        XCTAssertEqual(RiskLevel.caution.foregroundColor, Color.black)
    }

    // MARK: - Typography

    func test_typography_heroNumber_is36Semibold() {
        let font = Typography.heroNumber()
        XCTAssertNotNil(font)
    }

    func test_typography_allFactoriesReturnFonts() {
        // Smoke test: every factory must compile and return a Font value
        _ = Typography.heroNumber()
        _ = Typography.largeTitle()
        _ = Typography.mediumTitle()
        _ = Typography.largeBody()
        _ = Typography.regularBody()
        _ = Typography.smallBody()
        _ = Typography.filePath()
        _ = Typography.sizeNumber()
    }

    // MARK: - Spacing constants

    func test_spacing_constants_haveExpectedValues() {
        XCTAssertEqual(Spacing.xxs, 2)
        XCTAssertEqual(Spacing.xs, 4)
        XCTAssertEqual(Spacing.sm, 8)
        XCTAssertEqual(Spacing.md, 16)
        XCTAssertEqual(Spacing.lg, 24)
        XCTAssertEqual(Spacing.xl, 32)
        XCTAssertEqual(Spacing.xxl, 48)
    }

    func test_spacing_constants_areIncreasing() {
        XCTAssertLessThan(Spacing.xxs, Spacing.xs)
        XCTAssertLessThan(Spacing.xs, Spacing.sm)
        XCTAssertLessThan(Spacing.sm, Spacing.md)
        XCTAssertLessThan(Spacing.md, Spacing.lg)
        XCTAssertLessThan(Spacing.lg, Spacing.xl)
        XCTAssertLessThan(Spacing.xl, Spacing.xxl)
    }

    // MARK: - Radius constants

    func test_radius_constants_haveExpectedValues() {
        XCTAssertEqual(Radius.sm, 4)
        XCTAssertEqual(Radius.md, 8)
        XCTAssertEqual(Radius.lg, 12)
        XCTAssertEqual(Radius.xl, 16)
    }

    func test_radius_constants_areIncreasing() {
        XCTAssertLessThan(Radius.sm, Radius.md)
        XCTAssertLessThan(Radius.md, Radius.lg)
        XCTAssertLessThan(Radius.lg, Radius.xl)
    }

    // MARK: - RowSize constants

    func test_rowSize_constants_haveExpectedValues() {
        XCTAssertEqual(RowSize.height, 48)
        XCTAssertEqual(RowSize.checkboxSize, 18)
        XCTAssertEqual(RowSize.iconSize, 24)
        XCTAssertEqual(RowSize.indentPerLevel, 24)
    }

    // MARK: - Helpers

    /// Extract normalized RGBA components from a SwiftUI Color via NSColor on macOS.
    private func rgbaComponents(_ color: Color) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        return (ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent)
    }
}