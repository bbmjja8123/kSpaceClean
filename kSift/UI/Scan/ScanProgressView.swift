import SwiftUI
import DesignSystem

struct ScanProgressView: View {
    let progress: ScanProgress
    let groupsFound: Int
    let elapsed: TimeInterval
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ProgressRing(progress: progress.progress)
                .frame(width: 120, height: 120)

            Text(phaseTitle)
                .font(.headline)
            Text(String(format: NSLocalizedString("%lld files scanned", comment: "Scanned file count"), progress.filesScanned))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                metricRow(
                    title: NSLocalizedString("Groups found", comment: "Scan groups found label"),
                    value: "\(groupsFound)"
                )
                metricRow(
                    title: NSLocalizedString("Elapsed", comment: "Scan elapsed time label"),
                    value: formatElapsed(elapsed)
                )
                if let currentPath = progress.currentPath {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("Current folder", comment: "Current scan folder label"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(currentPath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: 240, alignment: .leading)
                }
            }

            if progress.duplicatesFound > 0 {
                Text(String(format: NSLocalizedString("%lld duplicates found", comment: "Duplicate count"), progress.duplicatesFound))
                    .foregroundColor(.brandPrimary)
            }

            ProgressView(value: progress.progress)
                .progressViewStyle(.linear)
                .frame(width: 200)

            Button(NSLocalizedString("Cancel scan", comment: "Cancel scan button"), role: .destructive, action: onCancel)
                .tint(.red)
        }
        .padding()
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .frame(width: 240)
    }

    private func formatElapsed(_ elapsed: TimeInterval) -> String {
        let totalSeconds = max(0, Int(elapsed.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var phaseTitle: String {
        switch progress.phase {
        case .enumerating: return NSLocalizedString("Scanning files...", comment: "Scan phase title")
        case .byteIdentical: return NSLocalizedString("Checking identical files...", comment: "Scan phase title")
        case .directoryDedup: return NSLocalizedString("Cross-directory analysis...", comment: "Scan phase title")
        case .perceptual: return NSLocalizedString("Comparing images...", comment: "Scan phase title")
        case .largeFiles: return NSLocalizedString("Finding large files...", comment: "Scan phase title")
        case .buildArtifacts: return NSLocalizedString("Identifying build artifacts...", comment: "Scan phase title")
        case .rawJPEG: return NSLocalizedString("Matching RAW + JPEG pairs...", comment: "Scan phase title")
        case .completed: return NSLocalizedString("Scan complete!", comment: "Scan phase title")
        }
    }
}
