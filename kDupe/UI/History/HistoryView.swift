import SwiftUI
import DesignSystem

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scan History")
                .font(.title).bold()
                .padding(.horizontal)

            if viewModel.isLoading {
                Spacer()
                LoadingStateView(title: NSLocalizedString("Loading history...", comment: "History loading"))
                Spacer()
            } else if viewModel.records.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "clock",
                    title: NSLocalizedString("No scans yet", comment: "Empty history title"),
                    subtitle: NSLocalizedString("Run a scan to see history here", comment: "Empty history subtitle")
                )
                Spacer()
            } else {
                List {
                    ForEach(viewModel.records) { record in
                        NavigationLink(destination: HistoryDetailView(record: record)) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(record.timestamp, style: .date)
                                        .font(.headline)
                                    Text("\(record.groups.count) groups · \(formatBytes(record.totalWasteSize))")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(record.duration.formatted())
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                Task { await viewModel.delete(record) }
                            }
                        }
                    }
                }
            }
        }
        .task { await viewModel.load() }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}