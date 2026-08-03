import SwiftUI
import DesignSystem

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var fdaStatus: FDAStatus = .unknown

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "doc.on.doc")
                .font(.system(size: 64))
                .foregroundColor(.brandPrimary)
            Text("Welcome to kSift")
                .font(.largeTitle).bold()
            Text("Find and remove duplicate files, reclaim disk space")
                .foregroundColor(.secondary)

            ProfileSetupView(viewModel: viewModel)
                .frame(maxWidth: 400)

            // Non-blocking permission card: green when granted, orange
            // call-out with "Open System Settings" / "Re-check" when denied.
            // The user can skip it and still finish onboarding.
            PermissionView(fdaStatus: $fdaStatus)
                .frame(maxWidth: 400)

            Spacer()

            Button(action: completeOnboarding) {
                Text("Get Started")
                    .frame(maxWidth: 300)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)
            .padding(.bottom, 40)
        }
        .onAppear {
            fdaStatus = FDAChecker.status()
        }
    }

    private func completeOnboarding() {
        let config = viewModel.buildConfig()
        // Persist so SettingsView reflects the onboarding choices on next
        // launch, and so MainView's first scan uses them instead of the
        // hard-coded ProfileConfig.default.
        viewModel.persist()
        appState.selectedProfile = viewModel.selectedProfile
        appState.isOnboardingComplete = true
        appState.navigation = .scan
        _ = config // keep the value visible until persistence is confirmed
    }
}
