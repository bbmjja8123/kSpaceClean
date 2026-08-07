import XCTest
import SwiftUI
@testable import DesignSystem

final class SparklineThemeTests: XCTestCase {

    func testAllThemesContainsExactlySevenEntries() {
        XCTAssertEqual(SparklineTheme.allThemes.count, 7,
                       "Spec requires exactly 7 sparkline themes")
    }

    func testEachThemeHasNonNilLineColorAndTwoStopGradient() {
        for theme in SparklineTheme.allThemes {
            XCTAssertFalse(theme.id.isEmpty,
                           "Theme must have a non-empty id (saw empty in \(theme.name))")
            XCTAssertFalse(theme.name.isEmpty,
                           "Theme \(theme.id) must have a non-empty display name")
            XCTAssertNotNil(theme.lineColor,
                            "Theme \(theme.id) must have a line color")
            XCTAssertEqual(theme.gradientColors.count, 2,
                           "Theme \(theme.id) gradient must have exactly 2 stops")
        }
    }

    func testDefaultThemeIsBlue() {
        XCTAssertEqual(SparklineTheme.default, .blue,
                       "Default sparkline theme must be the blue theme")
    }

    func testThemeLookupByKnownIDReturnsMatchingTheme() {
        let resolved = SparklineTheme.theme(forID: "blue")
        XCTAssertEqual(resolved, .blue)
    }

    func testThemeLookupByUnknownIDReturnsDefault() {
        let resolved = SparklineTheme.theme(forID: "nonexistent-theme-id")
        XCTAssertEqual(resolved, SparklineTheme.default)
    }

    func testAllThemeIDsAreUnique() {
        let ids = SparklineTheme.allThemes.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count,
                       "Theme ids must be unique across allThemes")
    }

    func testAllStaticThemeInstancesAreInAllThemes() {
        let allIDs = Set(SparklineTheme.allThemes.map(\.id))
        let staticIDs: [String] = [
            SparklineTheme.blue.id,
            SparklineTheme.green.id,
            SparklineTheme.purple.id,
            SparklineTheme.sunset.id,
            SparklineTheme.monochrome.id,
            SparklineTheme.vivid.id,
            SparklineTheme.muted.id,
        ]
        for id in staticIDs {
            XCTAssertTrue(allIDs.contains(id),
                          "Static theme \(id) must be present in allThemes")
        }
    }
}
