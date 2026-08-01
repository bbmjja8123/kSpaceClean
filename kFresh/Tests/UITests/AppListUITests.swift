import XCTest
@testable import kFresh

/// Placeholder UI test for the AppList main page.
///
/// Like ``OnboardingUITests``, this bundle hosts no dedicated UI test target
/// (it is a unit bundle hosted inside kFresh.app), so `XCUIApplication()`
/// cannot launch a second copy of the app. Until a UI test target exists,
/// this class guards the AppList feature contract — the sort keys and
/// categories the sidebar and toolbar expose — through the view model API.
final class AppListUITests: XCTestCase {
    func testSortKeyContractHasFourCasesInOrder() {
        let keys = AppListViewModel.SortKey.allCases
        XCTAssertEqual(keys.count, 4)
        XCTAssertEqual(keys.map(\.rawValue), ["name", "size", "installDate", "lastUsedDate"])
    }

    func testCategoryContractHasFourCasesInOrder() {
        let categories = AppListViewModel.Category.allCases
        XCTAssertEqual(categories.count, 4)
        XCTAssertEqual(categories.map(\.rawValue), ["all", "user", "system", "recentlyInstalled"])
    }

    func testSortKeyIdentifiableByRawValue() {
        for key in AppListViewModel.SortKey.allCases {
            XCTAssertEqual(key.id, key.rawValue)
        }
    }

    func testCategoryIdentifiableByRawValue() {
        for category in AppListViewModel.Category.allCases {
            XCTAssertEqual(category.id, category.rawValue)
        }
    }
}
