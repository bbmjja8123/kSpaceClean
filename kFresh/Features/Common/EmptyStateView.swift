import SwiftUI

struct EmptyStateView: View {
    let title: String
    let subtitle: String
    var icon: String = "tray"
    var action: (title: String, handler: () -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(AppFont.display)
                .foregroundColor(.brandSecondary.opacity(0.6))

            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundColor(.textPrimary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)

            if let action = action {
                Button(action.title, action: action.handler)
                    .buttonStyle(.brand)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
