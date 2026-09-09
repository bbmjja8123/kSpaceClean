// kWise/Tests/ToolTabTests.swift
//
// v2.5 Tab 化工具箱 — open/activate/close 生命周期与去重。
import XCTest
@testable import kWise

@MainActor
final class ToolTabTests: XCTestCase {

    func testOpenCreatesTabAndNavigates() {
        let state = AppState()
        state.openToolTab(.largeOld)
        XCTAssertEqual(state.toolTabs.count, 1)
        XCTAssertEqual(state.toolTabs.first?.item, .largeOld)
        XCTAssertEqual(state.activeToolTabID, state.toolTabs.first?.id)
        XCTAssertEqual(state.navigation, .largeOld)
    }

    func testOpenExistingActivatesWithoutDuplicate() {
        let state = AppState()
        state.openToolTab(.duplicates)
        let firstID = state.toolTabs.first?.id
        state.openToolTab(.duplicates)
        XCTAssertEqual(state.toolTabs.count, 1, "重复打开必须激活既有 Tab，不新建")
        XCTAssertEqual(state.activeToolTabID, firstID)
    }

    func testMultipleTabsRemainOpenAcrossNavigation() {
        let state = AppState()
        state.openToolTab(.duplicates)
        state.openToolTab(.largeOld)
        // 切去 rail 页（非工具）——Tab 必须保留。
        state.navigation = .smartCare
        XCTAssertEqual(state.toolTabs.count, 2, "切去 rail 页时 Tab 必须保留")
        // 激活其中一个 → 导航跟随。
        let dupTab = state.toolTabs.first { $0.item == .duplicates }!
        state.activateToolTab(dupTab.id)
        XCTAssertEqual(state.navigation, .duplicates)
    }

    func testCloseActiveFallsBackToLastRemaining() {
        let state = AppState()
        state.openToolTab(.duplicates)
        state.openToolTab(.largeOld)
        let largeOldTab = state.toolTabs.first { $0.item == .largeOld }!
        state.closeToolTab(largeOldTab.id)

        XCTAssertEqual(state.toolTabs.count, 1)
        XCTAssertEqual(state.navigation, .duplicates,
                       "关闭激活 Tab 必须落到最后一个剩余 Tab")
    }

    func testCloseLastNavigatesToToolboxGrid() {
        let state = AppState()
        state.openToolTab(.duplicates)
        let tab = state.toolTabs[0]
        state.closeToolTab(tab.id)
        XCTAssertEqual(state.toolTabs, [])
        XCTAssertEqual(state.navigation, .tools, "最后一个 Tab 关闭后回工具箱网格")
    }

    func testNonToolNavigationOpensNoTab() {
        let state = AppState()
        state.openToolTab(.scan)
        XCTAssertEqual(state.toolTabs, [], "rail 页不产生 Tab")
        XCTAssertEqual(state.navigation, .scan)
    }

    func testAllNineToolsAreToolboxTools() {
        let expected: [AppState.NavigationItem] = [
            .appUninstall, .duplicates, .largeOld, .photoClean,
            .shredder, .startupItems, .spaceMap, .maintenance, .assistant,
        ]
        for item in expected {
            XCTAssertTrue(item.isToolboxTool, "\(item) 应以 Tab 打开")
        }
        XCTAssertFalse(AppState.NavigationItem.smartCare.isToolboxTool)
        XCTAssertFalse(AppState.NavigationItem.scan.isToolboxTool)
    }
}
