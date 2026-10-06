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
        // P0 Task 9 added `.attribution` (toolbox deep surface).
        // P1 T1 adds `.anatomy` (rail head; SmartCare retired to deep link).
        // P1 T8 retires `.assistant` (Q&A embedded in DetailPanel) and the
        // dormant `.attribution` residue case (P1 T5 routed it to `.anatomy`).
        // P2 T7 retires `.monthlyReport` (merged into the history page).
        XCTAssertEqual(AppState.NavigationItem.allCases.count, 17)
    }

    /// v2.0 Phase 2: the rail was fixed at six entries and never grew.
    /// P2 T1 (Klaris 单一主画布)：rail 收敛至 3 项 —— 扫描/清理/工具全部
    /// 折进解剖画布（spec §2）。其余 case 保留编译（W4 才删）。
    func test_NavigationItem_railItems() {
        XCTAssertEqual(AppState.NavigationItem.railItems, [
            .anatomy, .history, .settings
        ])
        for item in AppState.NavigationItem.railItems {
            XCTAssertTrue(AppState.NavigationItem.allCases.contains(item))
        }
    }

    /// P2 T1: rail 收敛至 3 项（spec §2 —— 单一主画布）。
    func testRailCollapsedToThree() {
        XCTAssertEqual(AppState.NavigationItem.railItems, [.anatomy, .history, .settings],
                       "单一主画布：rail 3 项（spec §2）")
    }

    /// P1 T1: anatomy is the rail head; smartCare survives only as a deep
    /// link / Widget target (spec §3.1 — SmartCare 降级).
    /// P2 T1: rail 收敛后 count 断言同步为 3。
    func testAnatomyIsRailHeadAndSmartCareRetired() {
        XCTAssertEqual(AppState.NavigationItem.railItems.first, .anatomy)
        XCTAssertFalse(AppState.NavigationItem.railItems.contains(.smartCare),
                       "SmartCare 降级后不再占 rail 位（spec §3.1）")
        XCTAssertFalse(AppState.NavigationItem.railItems.contains(.scan),
                       "扫描并入解剖画布，不再占 rail 位（P2 spec §2）")
        XCTAssertFalse(AppState.NavigationItem.railItems.contains(.cleanup),
                       "清理并入解剖画布，不再占 rail 位（P2 spec §2）")
        XCTAssertFalse(AppState.NavigationItem.railItems.contains(.tools),
                       "工具箱改由画布承接，不再占 rail 位（P2 spec §2）")
        XCTAssertEqual(AppState.NavigationItem.railItems.count, 3)
    }

    func test_NavigationItem_tooltip_notEmpty() {
        for item in AppState.NavigationItem.allCases {
            XCTAssertFalse(item.tooltip.isEmpty, "Tooltip for \(item) should not be empty")
        }
    }
}
