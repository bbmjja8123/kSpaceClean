import SwiftUI
import DesignSystem

/// First onboarding page: welcome message and "Get Started" entry point.
struct WelcomePage: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.system(size: 56))
                .foregroundStyle(Color.brandSecondary)
            Text(String(localized: "Welcome to kWatch")).font(.title).bold()
            Text(String(localized: "Lightweight, sandbox-safe system monitoring for your Mac."))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Button(String(localized: "Get Started"), action: onNext)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
    }
}