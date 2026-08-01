import SwiftUI

struct LoadingStateView: View {
    let message: String
    var progress: Double? = nil

    var body: some View {
        VStack(spacing: 16) {
            if let progress = progress {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                    .tint(.brandPrimary)
            } else {
                ProgressView()
                    .scaleEffect(1.2)
            }

            Text(message)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
