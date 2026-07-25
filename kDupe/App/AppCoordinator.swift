import SwiftUI

@MainActor
public final class AppCoordinator: ObservableObject {
    public weak var appState: AppState?

    public init(appState: AppState? = nil) {
        self.appState = appState
    }

    @discardableResult
    public func handleDeepLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme, scheme == "kdupe",
              let host = url.host else { return false }
        switch host {
        case "scan":
            appState?.navigation = .scan
            return true
        case "results":
            appState?.navigation = .results
            return true
        default:
            return false
        }
    }

    public func navigate(to item: AppState.NavigationItem) {
        appState?.navigation = item
    }
}
