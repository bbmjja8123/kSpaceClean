import SwiftUI

@MainActor
class AppCoordinator: ObservableObject {
    @Published var selectedApp: InstalledApp?
    @Published var showPaywall = false
    @Published var showAbout = false
    @Published var showOnboarding: Bool
    @Published var showHistory = false
    @Published var showSettings = false

    var appState: AppState?

    /// Probes Full Disk Access. Shared so onboarding and later scans observe
    /// the same cached status rather than each re-checking the file system.
    let fdaProbe = FDAPermissionProbe()

    private let defaults: UserDefaults

    /// Creates the coordinator, showing onboarding only on first launch.
    ///
    /// - Parameter defaults: Store holding the onboarding completion flag.
    ///   Injectable for testing.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.showOnboarding = !defaults.bool(forKey: FDAGuideController.onboardingKey)
    }

    /// Builds the controller backing the onboarding flow.
    func makeOnboardingController() -> FDAGuideController {
        FDAGuideController(probe: fdaProbe, defaults: defaults)
    }

    /// Dismisses onboarding once the user finishes or skips it.
    func onboardingFinished() {
        showOnboarding = false
    }

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
