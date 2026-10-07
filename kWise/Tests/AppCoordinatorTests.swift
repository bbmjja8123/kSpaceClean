import XCTest
@testable import kWise

@MainActor
final class AppCoordinatorTests: XCTestCase {
    func test_handleDeepLink_scan_setsNavigation() {
        let appState = AppState()
        let coordinator = AppCoordinator(appState: appState)
        let url = URL(string: "klaris://scan?path=%2FUsers%2Fme%2FDownloads")!
        let result = coordinator.handleDeepLink(url)
        XCTAssertTrue(result)
        // P2 T9（spec §7 深链终态）：扫描是动作不是页面 —— Finder 扩展的
        // `scan?path=` 落解剖画布（hero 发起扫描）。
        XCTAssertEqual(appState.navigation, .anatomy)
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

    /// P2 T9（spec §7）：通知深链 → 历史时间线。
    func test_handleDeepLink_history_opensHistory() {
        let appState = AppState()
        let coordinator = AppCoordinator(appState: appState)
        let url = URL(string: "klaris://history")!
        let result = coordinator.handleDeepLink(url)
        XCTAssertTrue(result)
        XCTAssertEqual(appState.navigation, .history)
    }

    /// P2 T9：设置深链保留。
    func test_handleDeepLink_settings_opensSettings() {
        let appState = AppState()
        let coordinator = AppCoordinator(appState: appState)
        XCTAssertTrue(coordinator.handleDeepLink(URL(string: "klaris://settings")!))
        XCTAssertEqual(appState.navigation, .settings)
    }

    /// P2 T9（spec §2/§9）：退役表面的旧深链不再处理 —— 绝不把用户引向
    /// 不存在的表面，诚实返回 false。
    func test_handleDeepLink_retiredHosts_areUnhandled() {
        let appState = AppState()
        let coordinator = AppCoordinator(appState: appState)
        // report / monthlyreport 不在退役清单 —— P2 T7 裁定其诚实落到
        // 历史（月报内容并入历史叙事头），由 NarrativeHeaderTests 钉住。
        for host in ["clean", "privacy", "startup", "uninstall", "shred",
                     "tools", "spacemap",
                     "duplicates", "largefiles", "photoclean", "maintenance"] {
            let before = appState.navigation
            XCTAssertFalse(coordinator.handleDeepLink(URL(string: "klaris://\(host)")!),
                           "退役深链 \(host) 应未处理")
            XCTAssertEqual(appState.navigation, before,
                           "退役深链 \(host) 不得改变导航")
        }
    }

    func test_navigate() {
        let appState = AppState()
        let coordinator = AppCoordinator(appState: appState)
        coordinator.navigate(to: .settings)
        XCTAssertEqual(appState.navigation, .settings)
    }

    func test_navigate_withNilAppState_doesNotCrash() {
        let coordinator = AppCoordinator(appState: nil)
        coordinator.navigate(to: .anatomy) // should not crash
    }

    func test_handleDeepLink_withNilAppState_returnsTrue() {
        let coordinator = AppCoordinator(appState: nil)
        let url = URL(string: "klaris://scan")!
        let result = coordinator.handleDeepLink(url)
        XCTAssertTrue(result)
    }
}
