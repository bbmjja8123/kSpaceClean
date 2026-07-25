import Foundation

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var autoScan = true
    @Published var backupRetentionDays = 30
    @Published var hasFDA = false
    @Published var isPro = false

    private let authorizer = FDAuthorizer()

    init() {
        Task {
            let granted = await authorizer.checkFDA()
            await MainActor.run { self.hasFDA = granted }
        }
    }

    func requestFDA() {
        Task {
            await authorizer.requestFDA()
        }
    }

    func showPaywall() {
        print("Show paywall")
    }
}
