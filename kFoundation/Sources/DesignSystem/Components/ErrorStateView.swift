import SwiftUI

public struct ErrorStateView: View {
    let title: String
    let message: String
    let retryAction: (() -> Void)?

    public init(title: String, message: String, retryAction: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.retryAction = retryAction
    }

    public var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)).foregroundColor(.warning)
            Text(title).font(AppFont.title3).foregroundColor(.textPrimary)
            Text(message).font(AppFont.callout).foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
            if let retryAction = retryAction {
                Button("Retry") { retryAction() }
                    .buttonStyle(.borderedProminent).tint(.brandPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
