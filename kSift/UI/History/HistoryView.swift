import SwiftUI
import DesignSystem
import DetectionCore

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
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HistoryTrendChart(
                            points: viewModel.trendPoints,
                            distribution: viewModel.distribution,
                            totalScans: viewModel.totalScans,
                            totalReclaimed: viewModel.totalReclaimed
                        )
                        .padding(.horizontal)

                        recordsList
                            .padding(.horizontal)
                    }
                }
            }
        }
        .task { await viewModel.load() }
        .confirmationDialog(
            NSLocalizedString("Delete this scan record?", comment: "History delete confirm title"),
            isPresented: Binding(
                get: { viewModel.recordPendingDelete != nil },
                set: { if !$0 { viewModel.recordPendingDelete = nil } }
            )
        ) {
            Button(NSLocalizedString("Delete record", comment: "History delete confirm button"), role: .destructive) {
                if let record = viewModel.recordPendingDelete {
                    Task { await viewModel.delete(record) }
                }
                viewModel.recordPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { viewModel.recordPendingDelete = nil }
        } message: {
            Text(NSLocalizedString(
                "Only the history entry is removed — no files are affected.",
                comment: "History delete confirm message"
            ))
        }
    }

    private var recordsList: some View {
        List {
            ForEach(viewModel.records) { record in
                NavigationLink(destination: HistoryDetailView(record: record)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.timestamp, style: .date)
                                .font(.headline)
                            Text("\(record.groups.count) groups · \(formatBytes(record.totalWasteSize))")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        // Profile badge: which preset produced this scan.
                        Label(record.profileType.title, systemImage: profileIcon(record.profileType))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.brandPrimary.opacity(0.12))
                            .foregroundColor(.brandPrimary)
                            .clipShape(Capsule())
                        Text(record.duration.formatted())
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        viewModel.recordPendingDelete = record
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.inset)
        .frame(minHeight: 240)
    }

    private func profileIcon(_ profile: ProfileType) -> String {
        switch profile {
        case .developer: return "hammer.fill"
        case .photographer: return "camera.fill"
        case .designer: return "person.fill"
        case .custom: return "slider.horizontal.3"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
