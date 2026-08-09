import SwiftUI
import DesignSystem

/// Step 1 — Welcome screen. Sets the tone, no asks. Just explains what
/// kSift does and why the user wants it.
struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 96))
                .foregroundStyle(Color.brandPrimary.gradient)
                .padding(.bottom, AppSpacing.md)
            Text(NSLocalizedString("Welcome to kSift", comment: "Onboarding welcome title"))
                .font(.largeTitle).bold()
                .multilineTextAlignment(.center)
            Text(NSLocalizedString("Find and remove duplicate files, reclaim disk space", comment: "Onboarding welcome subtitle"))
                .font(.title3)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)

            // Three-bullet value prop. Concrete benefit per line — not a
            // "feature list" of marketing copy.
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                valueBullet(icon: "doc.on.doc",
                            title: NSLocalizedString("Find duplicates across your Mac", comment: "Onboarding value prop"),
                            body: NSLocalizedString("Byte-identical, near-duplicate images, RAW+JPEG pairs, and copy-paste folders.", comment: "Onboarding value prop detail"))
                valueBullet(icon: "lock.shield",
                            title: NSLocalizedString("Everything stays on your Mac", comment: "Onboarding value prop"),
                            body: NSLocalizedString("No uploads, no telemetry, no network calls during scanning.", comment: "Onboarding value prop detail"))
                valueBullet(icon: "trash",
                            title: NSLocalizedString("Trash + 30-day vault undo", comment: "Onboarding value prop"),
                            body: NSLocalizedString("Cleaned files move to a private vault you can restore for 30 days.", comment: "Onboarding value prop detail"))
            }
            .frame(maxWidth: 420)
            .padding(.top, AppSpacing.lg)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg)
    }

    @ViewBuilder
    private func valueBullet(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.brandPrimary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(body)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}