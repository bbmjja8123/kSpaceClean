import SwiftUI

public struct LoadingStateView: View {
    let title: String
    let progress: Double?
    let detail: String?

    public init(title: String, progress: Double? = nil, detail: String? = nil) {
        self.title = title
        self.progress = progress
        self.detail = detail
    }

    public var body: some View {
        VStack(spacing: AppSpacing.lg) {
            if let progress = progress {
                ProgressRing(progress: progress, label: "\(Int(progress * 100))%")
                    .frame(width: 80, height: 80)
            } else {
                ProgressView().scaleEffect(1.5)
            }
            Text(title).font(AppFont.title3).foregroundColor(.textPrimary)
            if let detail = detail {
                Text(detail).font(AppFont.caption).foregroundColor(.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
