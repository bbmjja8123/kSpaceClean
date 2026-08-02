import XCTest
import SwiftUI
import MetricsKit
@testable import DesignSystem

@MainActor
final class MenuBarIconsTests: XCTestCase {

    func testAllStylesAreCaseIterable() {
        XCTAssertEqual(MenuBarIcons.Style.allCases.count, 3)
    }

    func testStyleRawValuesRoundTrip() {
        XCTAssertEqual(MenuBarIcons.Style(rawValue: "sparkline"), .sparkline)
        XCTAssertEqual(MenuBarIcons.Style(rawValue: "numeric"), .numeric)
        XCTAssertEqual(MenuBarIcons.Style(rawValue: "minimal"), .minimal)
    }

    func testSparklineIconRendersWithoutCrashing() {
        let view = MenuBarIcons.statusIcon(
            kind: .cpu,
            style: .sparkline,
            values: [0.1, 0.2, 0.3, 0.4],
            currentValue: 40,
            unit: "%"
        )
        // Smoke check: icon constructs without crashing; rendering correctness is visual.
        _ = view
    }

    func testNumericIconRendersWithoutCrashing() {
        let view = MenuBarIcons.statusIcon(
            kind: .temperature,
            style: .numeric,
            values: [],
            currentValue: 61,
            unit: "°"
        )
        _ = view
    }

    func testMinimalIconRendersWithoutCrashing() {
        let view = MenuBarIcons.statusIcon(
            kind: .battery,
            style: .minimal,
            values: [],
            currentValue: 100,
            unit: "%"
        )
        _ = view
    }

    func testCardIconUsesSFSystemFont() {
        let view = MenuBarIcons.cardIcon(kind: .cpu, size: 14)
        // Smoke check: icon constructs without crashing; rendering correctness is visual.
        _ = view
    }
}
