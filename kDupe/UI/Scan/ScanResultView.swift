import SwiftUI
import DesignSystem

struct ScanResultView: View {
    let groups: [DuplicateGroup]
    let onReview: () -> Void
    let onRescan: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.success)

            Text("Scan Complete")
                .font(.title).bold()

            VStack(spacing: 8) {
                StatRow(label: "Duplicate Groups", value: "\(groups.count)")
                StatRow(label: "Wasteable Space", value: ByteCountFormatter.string(fromByteCount: totalWaste, countStyle: .file))
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))

            HStack(spacing: 16) {
                Button("Review Results", action: onReview)
                    .buttonStyle(.borderedProminent)
                Button("Rescan", action: onRescan)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private var totalWaste: Int64 {
        groups.reduce(0) { $0 + $1.totalSize }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).bold()
        }
    }
}
