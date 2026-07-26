import SwiftUI

/// Third onboarding page: introduce kWatch Pro without forcing the user
/// to upgrade. The page is fully dismissible via "Skip" — Task 12 must
/// never auto-present a paywall.
struct ProIntroPage: View {
    let onSkip: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "star.circle.fill").font(.system(size: 36)).foregroundStyle(.tint)
            Text("Meet kWatch Pro").font(.title2).bold()
            Text("Unlock temperature, fan, and battery readings, 30-day history, threshold alerts, interactive Widget, Live Activity, and 8 Shortcuts.")
                .foregroundStyle(.secondary)
            Text("One-time purchase of $7.99. You can upgrade anytime from Settings.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            Spacer()
            HStack {
                Button("Skip", action: onSkip)
                Spacer()
                Button("Continue", action: onContinue).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }
}