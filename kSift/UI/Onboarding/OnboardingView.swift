import SwiftUI
import DesignSystem

/// 3-step onboarding flow with progress dots and Back/Next navigation.
///
/// Step 1 — Welcome: brand + value prop, no asks
/// Step 2 — Profile: pick developer / designer / photographer (existing
///          ProfileSetupView, repackaged as ProfileStep content)
/// Step 3 — Permission + finalize: optional FDA grant + Get Started
///
/// State lives in `OnboardingViewModel.step` (already @Published).
/// Back/Next mutate `step`. `completeOnboarding` only fires from step 3.
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var fdaStatus: FDAStatus = .unknown

    private static let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            // Header: progress dots, fixed at the top.
            VStack(spacing: AppSpacing.md) {
                OnboardingProgressDots(totalSteps: Self.totalSteps,
                                       currentStep: viewModel.step)
                    .padding(.top, AppSpacing.xl)
            }

            // Step content. Each step owns its full-height scroll area.
            Group {
                switch viewModel.step {
                case 0:
                    OnboardingWelcomeStep()
                case 1:
                    profileStep
                case 2:
                    permissionStep
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer: Back / Next (or Get Started on the last step).
            footer
        }
        .background(Color.windowBackground.ignoresSafeArea())
        .onAppear { fdaStatus = FDAChecker.status() }
        .onChange(of: fdaStatus) { _ in /* keep UI in sync if user toggles System Settings */ }
    }

    // MARK: - Steps

    private var profileStep: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Text(NSLocalizedString("Choose Your Profile", comment: "Onboarding step 2 title"))
                    .font(.title).bold()
                Text(NSLocalizedString("kSift optimizes scanning based on your workflow", comment: "Onboarding step 2 subtitle"))
                    .foregroundColor(.secondary)
                ProfileSetupView(viewModel: viewModel)
                    .frame(maxWidth: 420)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.xl)
        }
    }

    private var permissionStep: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 64))
                    .foregroundColor(.brandPrimary)
                Text(NSLocalizedString("Grant Full Disk Access", comment: "Onboarding step 3 title"))
                    .font(.title).bold()
                Text(NSLocalizedString("Required to scan protected folders like Desktop, Documents, and Downloads.", comment: "Onboarding step 3 subtitle"))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, AppSpacing.xl)

                PermissionView(fdaStatus: $fdaStatus)
                    .frame(maxWidth: 420)

                Text(NSLocalizedString("You can skip this and grant later in Settings.", comment: "Onboarding skip permission hint"))
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .padding(.top, AppSpacing.sm)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.xl)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: AppSpacing.md) {
            // Back button — hidden on step 0.
            if viewModel.step > 0 {
                Button(NSLocalizedString("Back", comment: "Onboarding back button")) {
                    viewModel.step -= 1
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            // Next vs. Get Started. Get Started only on the last step.
            if viewModel.step < Self.totalSteps - 1 {
                Button(NSLocalizedString("Next", comment: "Onboarding next button")) {
                    viewModel.step += 1
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandPrimary)
                .keyboardShortcut(.defaultAction)
            } else {
                Button(NSLocalizedString("Get Started", comment: "Onboarding finish button"),
                       action: completeOnboarding)
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.lg)
        .background(.regularMaterial)
    }

    private func completeOnboarding() {
        viewModel.persist()
        appState.selectedProfile = viewModel.selectedProfile
        appState.isOnboardingComplete = true
        appState.navigation = .scan
    }
}