import SwiftUI

@MainActor
class AppCoordinator: ObservableObject {
    @Published var selectedApp: InstalledApp?
    @Published var showPaywall = false
    @Published var showOnboarding = false
    @Published var showHistory = false
    @Published var showSettings = false

    var appState: AppState?

    func handleDeepLink(_ url: URL) {
        // Handle incoming URL schemes
    }

    func selectApp(_ app: InstalledApp) {
        selectedApp = app
    }

    func navigateToHistory() {
        showHistory = true
    }
}
