import XCTest
@testable import kWise

@MainActor
final class AppStateTests: XCTestCase {
    func test_initialState() {
        let state = AppState()
        // P1 T1: SmartCare 降级为深链面 — 首屏让位给空间解剖（spec §3.1）。
        XCTAssertEqual(state.navigation, .anatomy)
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
        // P0 Task 9 adds `.attribution` (toolbox deep surface).
        // P1 T1 adds `.anatomy` (rail head; SmartCare retired to deep link).
        XCTAssertEqual(AppState.NavigationItem.allCases.count, 20)
    }

    /// v2.0 Phase 2: the rail is fixed at six entries and never grows.
    /// P1 T1: `.anatomy` takes the rail head; `.smartCare` leaves the rail.
    func test_NavigationItem_railItems() {
        XCTAssertEqual(AppState.NavigationItem.railItems, [
            .anatomy, .scan, .tools, .cleanup, .history, .settings
        ])
        for item in AppState.NavigationItem.railItems {
            XCTAssertTrue(AppState.NavigationItem.allCases.contains(item))
        }
    }

    /// P1 T1: anatomy is the rail head; smartCare survives only as a deep
    /// link / Widget target (spec §3.1 — SmartCare 降级).
    func testAnatomyIsRailHeadAndSmartCareRetired() {
        XCTAssertEqual(AppState.NavigationItem.railItems.first, .anatomy)
        XCTAssertFalse(AppState.NavigationItem.railItems.contains(.smartCare),
                       "SmartCare 降级后不再占 rail 位（spec §3.1）")
        XCTAssertEqual(AppState.NavigationItem.railItems.count, 6)
    }

    func test_NavigationItem_tooltip_notEmpty() {
        for item in AppState.NavigationItem.allCases {
            XCTAssertFalse(item.tooltip.isEmpty, "Tooltip for \(item) should not be empty")
        }
    }
}
