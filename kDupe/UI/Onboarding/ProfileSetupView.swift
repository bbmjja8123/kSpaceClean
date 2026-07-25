import SwiftUI
import DesignSystem

struct ProfileSetupView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Text("Choose Your Profile")
                .font(.title2).bold()
            Text("kDupe optimizes scanning based on your workflow")
                .foregroundColor(.secondary)

            ForEach(ProfileType.allCases, id: \.self) { profile in
                Button(action: { viewModel.selectedProfile = profile }) {
                    HStack {
                        Image(systemName: iconFor(profile))
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text(profile.title).bold()
                            Text(descriptionFor(profile))
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if viewModel.selectedProfile == profile {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.brandPrimary)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg)
                            .stroke(viewModel.selectedProfile == profile ? Color.brandPrimary : .clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    private func iconFor(_ profile: ProfileType) -> String {
        switch profile {
        case .developer: return "terminal"
        case .photographer: return "camera"
        case .simple: return "person"
        }
    }

    private func descriptionFor(_ profile: ProfileType) -> String {
        switch profile {
        case .developer: return "Scans projects, build artifacts, and development directories"
        case .photographer: return "Scans photos, RAW files, and creative assets"
        case .simple: return "Scans desktop, downloads, and documents"
        }
    }
}
