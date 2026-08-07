import SwiftUI
import DesignSystem

/// Third onboarding page: introduce kWatch Pro without forcing the user
/// to upgrade. The page is fully dismissible via "Skip" — Task 12 must
/// never auto-present a paywall.
struct ProIntroPage: View {
    let onSkip: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "star.circle.fill").font(.system(size: 36)).foregroundStyle(Color.brandSecondary)
            Text(String(localized: "Meet kWatch Pro")).font(.title2).bold()
            Text(String(localized: "Unlock temperature, fan, and battery readings, 30-day history, threshold alerts, interactive Widget, Live Activity, and 8 Shortcuts."))
                .foregroundStyle(Color.textSecondary)
            Text(String(localized: "One-time purchase of $7.99. You can upgrade anytime from Settings."))
                .font(.footnote)
                .foregroundStyle(Color.textSecondary.opacity(0.6))
            Spacer()
            HStack {
                Button(String(localized: "Skip"), action: onSkip)
                Spacer()
                Button(String(localized: "Continue"), action: onContinue).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }
}