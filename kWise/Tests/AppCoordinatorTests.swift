import XCTest
@testable import kWise

@MainActor
final class AppCoordinatorTests: XCTestCase {
    func test_handleDeepLink_scan_setsNavigation() {
        let appState = AppState()
        let coordinator = AppCoordinator(appState: appState)
        let url = URL(string: "klaris://scan")!
        let result = coordinator.handleDeepLink(url)
        XCTAssertTrue(result)
        XCTAssertEqual(appState.navigation, .scan)
    }

    func test_handleDeepLink_unknownHost_returnsFalse() {
        let appState = AppState()
        let coordinator = AppCoordinator(appState: appState)
        let url = URL(string: "klaris://unknown")!
        let result = coordinator.handleDeepLink(url)
        XCTAssertFalse(result)
    }

    func test_handleDeepLink_wrongScheme_returnsFalse() {
        let appState = AppState()
        let coordinator = AppCoordinator(appState: appState)
        let url = URL(string: "other://scan")!
        let result = coordinator.handleDeepLink(url)
        XCTAssertFalse(result)
    }

    func test_handleDeepLink_noHost_returnsFalse() {
        let appState = AppState()
        let coordinator = AppCoordinator(appState: appState)
        let url = URL(string: "klaris://")!
        let result = coordinator.handleDeepLink(url)
        XCTAssertFalse(result)
    }

    /// P1 T1: SmartCare 降级后 `klaris://smartcare`（Widget 一键清理按钮、
    /// 通知深链）应落在解剖首屏，而不是已下线的 Smart Care 页（R1）。
    func test_handleDeepLink_smartCare_opensAnatomy() {
        let appState = AppState()
        let coordinator = AppCoordinator(appState: appState)
        let url = URL(string: "klaris://smartcare")!
        let result = coordinator.handleDeepLink(url)
        XCTAssertTrue(result)
        XCTAssertEqual(appState.navigation, .anatomy,
                       "SmartCare 降级：深链与 Widget 按钮应落在解剖首屏（R1）")
    }

    /// P2 T1: DiskHealthCard 已内嵌解剖画布（spec §7）——`klaris://health`
    /// 深链落首屏 `.anatomy`，不再跳独立磁盘健康详情页。
    func test_handleDeepLink_health_opensAnatomy() {
        let appState = AppState()
        let coordinator = AppCoordinator(appState: appState)
        let url = URL(string: "klaris://health")!
        let result = coordinator.handleDeepLink(url)
        XCTAssertTrue(result)
        XCTAssertEqual(appState.navigation, .anatomy,
                       "health 深链：DiskHealthCard 已在画布上，应落解剖首屏（P2 spec §7）")
    }

    func test_navigate() {
        let appState = AppState()
        let coordinator = AppCoordinator(appState: appState)
        coordinator.navigate(to: .settings)
        XCTAssertEqual(appState.navigation, .settings)
    }

    func test_navigate_withNilAppState_doesNotCrash() {
        let coordinator = AppCoordinator(appState: nil)
        coordinator.navigate(to: .scan) // should not crash
    }

    func test_handleDeepLink_withNilAppState_returnsTrue() {
        let coordinator = AppCoordinator(appState: nil)
        let url = URL(string: "klaris://scan")!
        let result = coordinator.handleDeepLink(url)
        XCTAssertTrue(result)
    }
}
