import SwiftUI
import DesignSystem

/// Read-only summary of a past scan. The user can browse the duplicate
/// groups found at the time and, if they want to delete any of them, drill
/// into the same `GroupDetailView` used by the live result screen.
struct HistoryDetailView: View {
    let record: ScanRecord

    var body: some View {
        VStack(spacing: 0) {
            // Header: timestamp + aggregate stats
            GlassPanel {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.timestamp, style: .date)
                            .font(.headline)
                        Text(record.timestamp, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    StatItem(title: "Groups", value: "\(record.groups.count)")
                    StatItem(title: "Waste", value: formatBytes(record.totalWasteSize))
                    StatItem(title: "Duration", value: record.duration.formatted())
                }
                .padding(12)
            }
            .padding(8)

            if record.groups.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "doc.on.doc",
                    title: NSLocalizedString("No groups in this scan", comment: "Empty scan detail title"),
                    subtitle: NSLocalizedString("The scan finished without finding any duplicates.", comment: "Empty scan detail subtitle")
                )
                Spacer()
            } else {
                List {
                    ForEach(record.groups) { group in
                        NavigationLink(destination: GroupDetailView(group: group)) {
                            GroupRowView(group: group)
                        }
                    }
                }
            }
        }
        .navigationTitle(record.timestamp.formatted(date: .abbreviated, time: .shortened))
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}