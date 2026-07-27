import SwiftUI

@MainActor
public final class AppCoordinator: ObservableObject {
    public weak var appState: AppState?

    public init(appState: AppState? = nil) {
        self.appState = appState
    }

    /// Handle incoming deep link URL
    @discardableResult
    public func handleDeepLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme, scheme == "kspaceclean",
              let host = url.host else { return false }

        switch host {
        case "scan":
            appState?.navigation = .scan
            return true
        default:
            return false
        }
    }

    /// Navigate to a specific page
    public func navigate(to item: AppState.NavigationItem) {
        appState?.navigation = item
    }
}
