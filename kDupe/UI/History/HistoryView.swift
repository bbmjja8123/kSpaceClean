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
                LoadingStateView(message: "Loading history...")
                Spacer()
            } else if viewModel.records.isEmpty {
                Spacer()
                EmptyStateView(icon: "clock", title: "No scans yet",
                              message: "Run a scan to see history here")
                Spacer()
            } else {
                List {
                    ForEach(viewModel.records) { record in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(record.date, style: .date)
                                    .font(.headline)
                                Text("\(record.groupCount) groups · \(formatBytes(record.totalSize))")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(record.duration.formatted())
                                .font(.caption).foregroundColor(.secondary)
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
