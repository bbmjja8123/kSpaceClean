import XCTest
import DesignSystem
import MetricsKit
@testable import kWatch

final class MenuBarIconThemeTests: XCTestCase {

    func testDefaultStyleForAnyMetricIsSparkline() {
        let theme = MenuBarIconTheme.default
        XCTAssertEqual(theme.style(for: .cpu), .sparkline)
        XCTAssertEqual(theme.style(for: .temperature), .sparkline)
    }

    func testSettingStylePerMetricIsRespected() {
        var theme = MenuBarIconTheme.default
        theme.set(.numeric, for: .cpu)
        theme.set(.minimal, for: .battery)
        XCTAssertEqual(theme.style(for: .cpu), .numeric)
        XCTAssertEqual(theme.style(for: .battery), .minimal)
        XCTAssertEqual(theme.style(for: .memory), .sparkline, "Untouched metrics retain default")
    }

    func testThemeIsCodable() throws {
        var theme = MenuBarIconTheme.default
        theme.set(.minimal, for: .fan)
        let data = try JSONEncoder().encode(theme)
        let decoded = try JSONDecoder().decode(MenuBarIconTheme.self, from: data)
        XCTAssertEqual(decoded.style(for: .fan), .minimal)
    }
}
