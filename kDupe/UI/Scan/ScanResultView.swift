import SwiftUI
import DesignSystem

struct ScanResultView: View {
    let groups: [DuplicateGroup]
    let onReview: () -> Void
    let onRescan: () -> Void

    var body: some View {
        if groups.isEmpty {
            // Empty-state branch: positive reinforcement + actionable next
            // step ("scan another folder") instead of a flat "0 groups".
            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundColor(.success)
                Text(NSLocalizedString("No duplicates found", comment: "Empty scan heading"))
                    .font(.title).bold()
                Text(NSLocalizedString("This folder looks tidy. Try scanning a different folder to find more.", comment: "Empty scan subtext"))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 360)
                Button(NSLocalizedString("Scan another folder", comment: "Empty scan CTA"), action: onRescan)
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
            }
            .padding()
        } else {
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
    }

    private var totalWaste: Int64 {
        groups.reduce(0) { $0 + $1.totalSize }
    }
}

struct StatRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).bold()
        }
    }
}
