import XCTest
@testable import kSpaceClean

@MainActor
final class AppCoordinatorTests: XCTestCase {
    func test_handleDeepLink_scan_setsNavigation() {
        let appState = AppState()
        let coordinator = AppCoordinator(appState: appState)
        let url = URL(string: "kspaceclean://scan")!
        let result = coordinator.handleDeepLink(url)
        XCTAssertTrue(result)
        XCTAssertEqual(appState.navigation, .scan)
    }

    func test_handleDeepLink_unknownHost_returnsFalse() {
        let appState = AppState()
        let coordinator = AppCoordinator(appState: appState)
        let url = URL(string: "kspaceclean://unknown")!
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
        let url = URL(string: "kspaceclean://")!
        let result = coordinator.handleDeepLink(url)
        XCTAssertFalse(result)
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
        let url = URL(string: "kspaceclean://scan")!
        let result = coordinator.handleDeepLink(url)
        XCTAssertTrue(result)
    }
}
