import SwiftUI

/// Slim banner above the app list that reflects the current scan lifecycle:
/// a progress bar while scanning and an error row with a retry button when a
/// scan fails. Renders nothing when idle or completed.
struct ScanProgressBanner: View {
    let state: AppListViewModel.ScanState
    let onRefresh: () -> Void

    var body: some View {
        Group {
            switch state {
            case .scanning(let progress):
                ProgressView(value: progress) {
                    Text("正在扫描...")
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppSpacing.md)
            case .failed(let message):
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.danger)
                    Text(message)
                        .lineLimit(1)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button("重试", action: onRefresh)
                }
                .padding(.horizontal, AppSpacing.md)
                .background(Color.danger.opacity(0.12))
            case .idle, .completed:
                EmptyView()
            }
        }
        .frame(height: state.height)
        .animation(KFAnimation.easeInOut, value: state)
    }
}

private extension AppListViewModel.ScanState {
    /// Height contribution of the banner; zero when nothing is shown so the
    /// list column does not jump when the scan finishes.
    var height: CGFloat {
        switch self {
        case .scanning, .failed: return 36
        default: return 0
        }
    }
}
