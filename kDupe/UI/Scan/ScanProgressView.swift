import SwiftUI
import DesignSystem

struct ScanProgressView: View {
    let progress: ScanProgress

    var body: some View {
        VStack(spacing: 24) {
            ProgressRing(progress: progress.progress)
                .frame(width: 120, height: 120)

            Text(phaseTitle)
                .font(.headline)
            Text("\(progress.filesScanned) files scanned")
                .foregroundColor(.secondary)
            if progress.duplicatesFound > 0 {
                Text("\(progress.duplicatesFound) duplicates found")
                    .foregroundColor(.brandPrimary)
            }

            ProgressView(value: progress.progress)
                .progressViewStyle(.linear)
                .frame(width: 200)
        }
        .padding()
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
