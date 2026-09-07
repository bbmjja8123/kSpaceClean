import XCTest
@testable import kWise

@MainActor
final class AppStateTests: XCTestCase {
    func test_initialState() {
        let state = AppState()
        XCTAssertEqual(state.navigation, .smartCare)
        XCTAssertEqual(state.scanState, .idle)
        // UX 重构 Phase 1: the detail panel is auto-hidden until selected.
        XCTAssertFalse(state.rightPanelVisible)
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

    func test_rightPanelVisible_toggle() {
        let state = AppState()
        state.rightPanelVisible = true
        XCTAssertTrue(state.rightPanelVisible)
        state.rightPanelVisible = false
        XCTAssertFalse(state.rightPanelVisible)
    }

    func test_selectedCategory() {
        let state = AppState()
        state.selectedCategory = .image
        XCTAssertEqual(state.selectedCategory, .image)
        state.selectedCategory = nil
        XCTAssertNil(state.selectedCategory)
    }

    func test_NavigationItem_allCases() {
        // v2.0 Phase 2: 11 original + 8 new (tools/spaceMap/monthlyReport/
        // assistant/duplicates/largeOld/photoClean/maintenance) − galaxy.
        XCTAssertEqual(AppState.NavigationItem.allCases.count, 18)
    }

    /// v2.0 Phase 2: the rail is fixed at six entries and never grows.
    func test_NavigationItem_railItems() {
        XCTAssertEqual(AppState.NavigationItem.railItems, [
            .smartCare, .scan, .tools, .cleanup, .history, .settings
        ])
        for item in AppState.NavigationItem.railItems {
            XCTAssertTrue(AppState.NavigationItem.allCases.contains(item))
        }
    }

    func test_NavigationItem_tooltip_notEmpty() {
        for item in AppState.NavigationItem.allCases {
            XCTAssertFalse(item.tooltip.isEmpty, "Tooltip for \(item) should not be empty")
        }
    }
}
