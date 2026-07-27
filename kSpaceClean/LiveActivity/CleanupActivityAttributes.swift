import SwiftUI

// MARK: - Live Activity for Cleanup Progress (macOS 14+)

#if canImport(ActivityKit)
import ActivityKit

struct CleanupActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var progress: Double        // 0.0 ... 1.0
        var currentFile: String
        var freedBytes: Int64
    }

    var startedAt: Date
}

// MARK: - Live Activity View (macOS 14+)

struct CleanupLiveActivityView: View {
    let context: ActivityViewContext<CleanupActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            // Left: cleanup icon
            Image(systemName: "trash.fill")
                .font(.title2)
                .foregroundColor(.brandPrimary)

            // Center: progress info
            VStack(alignment: .leading, spacing: 4) {
                Text("Cleaning...")
                    .font(.headline)

                Text(context.state.currentFile)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                ProgressView(value: context.state.progress)
                    .tint(.brandPrimary)
            }

            // Right: freed space
            VStack(alignment: .trailing) {
                Text("\(formatBytes(context.state.freedBytes))")
                    .font(.caption).fontWeight(.medium)
                Text("freed")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding()
        .activityBackgroundTint(.clear)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
#else
// ActivityKit not available on this macOS version
struct CleanupActivityAttributes: Codable, Hashable {
    var startedAt: Date
}

struct CleanupLiveActivityView: View {
    var body: some View {
        EmptyView()
    }
}
#endif
