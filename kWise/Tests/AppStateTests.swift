import XCTest
@testable import kWise

@MainActor
final class AppStateTests: XCTestCase {
    func test_initialState() {
        let state = AppState()
        // P1 T1: SmartCare 降级为深链面 — 首屏让位给空间解剖（spec §3.1）。
        XCTAssertEqual(state.navigation, .anatomy)
        XCTAssertEqual(state.scanState, .idle)
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

    func test_selectedCategory() {
        let state = AppState()
        state.selectedCategory = .image
        XCTAssertEqual(state.selectedCategory, .image)
        state.selectedCategory = nil
        XCTAssertNil(state.selectedCategory)
    }

    func test_NavigationItem_allCases() {
        // P2 T9（spec §2/§9）：~20 表面收敛为 6 —— 可导航面只剩 3：
        // 解剖画布（含下钻路由）/ 历史 / 设置；粉碎窗与磁盘健康详情走
        // sheet，不占导航枚举。
        XCTAssertEqual(AppState.NavigationItem.allCases.count, 3)
        XCTAssertEqual(AppState.NavigationItem.allCases,
                       [.anatomy, .history, .settings])
    }

    /// v2.0 Phase 2: the rail was fixed at six entries and never grew.
    /// P2 T1 (Klaris 单一主画布)：rail 收敛至 3 项；P2 T9 起与 allCases 恒等。
    func test_NavigationItem_railItems() {
        XCTAssertEqual(AppState.NavigationItem.railItems, [
            .anatomy, .history, .settings
        ])
        XCTAssertEqual(AppState.NavigationItem.railItems,
                       AppState.NavigationItem.allCases,
                       "rail 之外不再存在可导航面")
    }

    /// P2 T1: rail 收敛至 3 项（spec §2 —— 单一主画布）。
    func testRailCollapsedToThree() {
        XCTAssertEqual(AppState.NavigationItem.railItems, [.anatomy, .history, .settings],
                       "单一主画布：rail 3 项（spec §2）")
    }

    /// P1 T1: anatomy is the rail head; smartCare survives only as a deep
    /// link / Widget target (spec §3.1 — SmartCare 降级).
    /// P2 T9：退役 case（scan/cleanup/tools/smartCare…）全部删除 —— 用
    /// rawValue 断言，杜绝同名 case 复活。
    func testAnatomyIsRailHeadAndRetiredCasesStayRetired() {
        XCTAssertEqual(AppState.NavigationItem.railItems.first, .anatomy)
        let rawValues = Set(AppState.NavigationItem.allCases.map(\.rawValue))
        for retired in ["scan", "cleanup", "tools", "smartCare", "spaceMap",
                        "privacy", "diskHealth", "startupItems", "appUninstall",
                        "shredder", "duplicates", "largeOld", "photoClean",
                        "maintenance"] {
            XCTAssertFalse(rawValues.contains(retired),
                           "退役导航面 \(retired) 不得复活（P2 spec §9）")
        }
        XCTAssertEqual(AppState.NavigationItem.railItems.count, 3)
    }

    func test_NavigationItem_tooltip_notEmpty() {
        for item in AppState.NavigationItem.allCases {
            XCTAssertFalse(item.tooltip.isEmpty, "Tooltip for \(item) should not be empty")
        }
    }
}
