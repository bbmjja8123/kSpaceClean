import SwiftUI
import DesignSystem

/// Dot-row progress indicator used by the 3-step onboarding. Three dots;
/// the current step dot is wider / brand-colored. Tappable for fast-jump
/// once the user has already passed it (no jumping backwards).
struct OnboardingProgressDots: View {
    let totalSteps: Int
    let currentStep: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step == currentStep ? Color.brandPrimary : Color.textSecondary.opacity(0.3))
                    .frame(width: step == currentStep ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
    }
}