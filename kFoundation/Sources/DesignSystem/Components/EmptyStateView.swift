import SwiftUI

public struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String?
    let action: (title: String, handler: () -> Void)?

    public init(icon: String, title: String, subtitle: String? = nil,
                action: (title: String, handler: () -> Void)? = nil) {
        self.icon = icon; self.title = title; self.subtitle = subtitle; self.action = action
    }

    public var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.textSecondary)
            Text(title).font(AppFont.title3).foregroundColor(.textPrimary)
            if let subtitle = subtitle {
                Text(subtitle).font(AppFont.callout).foregroundColor(.textSecondary)
            }
            if let action = action {
                Button(action.title) { action.handler() }
                    .buttonStyle(.borderedProminent).tint(.brandPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
