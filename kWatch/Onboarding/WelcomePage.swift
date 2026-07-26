import SwiftUI

/// First onboarding page: welcome message and "Get Started" entry point.
struct WelcomePage: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Welcome to kWatch").font(.title).bold()
            Text("Lightweight, sandbox-safe system monitoring for your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Get Started", action: onNext)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
    }
}