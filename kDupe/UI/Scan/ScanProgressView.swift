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
        case .enumerating: return "Scanning files..."
        case .byteIdentical: return "Checking identical files..."
        case .directoryDedup: return "Cross-directory analysis..."
        case .perceptual: return "Comparing images..."
        case .largeFiles: return "Finding large files..."
        case .buildArtifacts: return "Identifying build artifacts..."
        case .rawJPEG: return "Matching RAW + JPEG pairs..."
        case .completed: return "Scan complete!"
        }
    }
}
