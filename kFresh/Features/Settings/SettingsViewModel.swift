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

    /// Creates the view model.
    ///
    /// - Parameter probe: Supplies the Full Disk Access status shown in Settings.
    init(probe: FDAPermissionProbe = FDAPermissionProbe()) {
        self.probe = probe
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

    func showPaywall() {
        print("Show paywall")
    }
}
