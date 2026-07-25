import SwiftUI

public struct ProgressRing: View {
    let progress: Double  // 0.0 ... 1.0
    let label: String?

    public init(progress: Double, label: String? = nil) {
        self.progress = min(max(progress, 0), 1)
        self.label = label
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.separatorColor.opacity(0.3), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.brandPrimary, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: progress)
            if let label = label {
                Text(label)
                    .font(AppFont.callout)
                    .foregroundColor(.textPrimary)
            }
        }
    }
}
