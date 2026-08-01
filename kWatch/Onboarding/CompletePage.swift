import SwiftUI
import DesignSystem

/// Final onboarding page: confirm completion and prompt the user to
/// reveal the kWatch menu-bar icon.
struct CompletePage: View {
    let onOpenMenuBar: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.success)
            Text("You're all set").font(.title2).bold()
            Text("Click the kWatch icon in your menu bar to see live metrics.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Button("Show in Menu Bar", action: onOpenMenuBar)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
    }
}