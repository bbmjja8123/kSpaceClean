import XCTest
@testable import kSpaceClean

@MainActor
final class AppStateTests: XCTestCase {
    func test_initialState() {
        let state = AppState()
        XCTAssertEqual(state.navigation, .galaxy)
        XCTAssertEqual(state.scanState, .idle)
        XCTAssertTrue(state.rightPanelVisible)
        XCTAssertEqual(state.rightPanelTab, .overview)
        XCTAssertNil(state.selectedCategory)
    }

    func test_navigation_change() {
        let state = AppState()
        state.navigation = .settings
        XCTAssertEqual(state.navigation, .settings)
    }

    func test_scanState_transitions() {
        let state = AppState()
        state.scanState = .scanning(0.5)
        if case .scanning(let progress) = state.scanState {
            XCTAssertEqual(progress, 0.5)
        } else {
            XCTFail("Expected .scanning state")
        }
    }

    func test_toggleRightPanel() {
        let state = AppState()
        state.rightPanelVisible = true
        XCTAssertTrue(state.rightPanelVisible)
        state.rightPanelVisible = false
        XCTAssertFalse(state.rightPanelVisible)
    }

    func test_rightPanelTab_change() {
        let state = AppState()
        state.rightPanelTab = .results
        XCTAssertEqual(state.rightPanelTab, .results)
        state.rightPanelTab = .suggestions
        XCTAssertEqual(state.rightPanelTab, .suggestions)
    }

    func test_selectedCategory() {
        let state = AppState()
        state.selectedCategory = .image
        XCTAssertEqual(state.selectedCategory, .image)
        state.selectedCategory = nil
        XCTAssertNil(state.selectedCategory)
    }

    func test_NavigationItem_allCases() {
        XCTAssertEqual(AppState.NavigationItem.allCases.count, 5)
    }

    func test_NavigationItem_tooltip_notEmpty() {
        for item in AppState.NavigationItem.allCases {
            XCTAssertFalse(item.tooltip.isEmpty, "Tooltip for \(item) should not be empty")
        }
    }
}
