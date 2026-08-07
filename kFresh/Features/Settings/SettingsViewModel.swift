import Foundation

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var autoScan = true
    @Published var backupRetentionDays = 30
    @Published var fdaStatus: FDAStatus = .unknown
    @Published var isPro = false

    /// Whether Full Disk Access is currently granted.
    var hasFDA: Bool { fdaStatus == .full }

    private let probe: FDAPermissionProbe
    private let authorizer = FDAuthorizer()

    /// The app-wide coordinator. ``showPaywall()`` sets `coordinator.showPaywall`
    /// so ``RootView`` presents the store paywall as a sheet (C3).
    private let coordinator: AppCoordinator

    /// Creates the view model.
    ///
    /// - Parameters:
    ///   - probe: Supplies the Full Disk Access status shown in Settings.
    ///   - coordinator: Receives the `showPaywall` signal for the paywall sheet.
    init(probe: FDAPermissionProbe = FDAPermissionProbe(), coordinator: AppCoordinator) {
        self.probe = probe
        self.coordinator = coordinator
        Task { await refreshFDAStatus() }
    }

    /// Re-checks Full Disk Access and republishes ``fdaStatus``.
    func refreshFDAStatus() async {
        fdaStatus = await probe.probe()
    }

    /// Opens System Settings, then re-checks so the row updates on return.
    ///
    /// The status also refreshes when the app regains activation from System
    /// Settings (via `NSApplication.didBecomeActiveNotification`), so a grant
    /// made in Settings is reflected without waiting for a manual re-trigger.
    func requestFDA() {
        authorizer.requestFDA()
        Task { await refreshFDAStatus() }
    }

    /// Presents the paywall by flagging ``AppCoordinator.showPaywall``; the
    /// ``RootView`` observes that flag and presents ``PaywallView`` as a sheet
    /// (C3).
    func showPaywall() {
        coordinator.showPaywall = true
    }

    /// Dismisses the Settings sheet before raising the paywall.
    ///
    /// Presenting the paywall while Settings is still on screen stacks a
    /// sheet on top of another sheet on macOS, which renders as a partially
    /// occluded window with no clear focus. Closing Settings first and
    /// re-raising the paywall on the next runloop tick gives the Settings
    /// sheet time to tear down before the new sheet appears.
    func dismissAndShowPaywall() {
        coordinator.showSettings = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [coordinator] in
            coordinator.showPaywall = true
        }
    }
}
