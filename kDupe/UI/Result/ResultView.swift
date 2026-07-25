import SwiftUI
import DesignSystem

struct ResultView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ResultViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Stats bar
            GlassPanel {
                HStack {
                    StatItem(title: "Groups", value: "\(viewModel.totalGroupCount)")
                    StatItem(title: "Duplicates", value: formatBytes(viewModel.totalDuplicateSize))
                    Spacer()
                    Button("Rescan") {
                        appState.navigation = .scan
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Filter bar
            FilterBarView(activeCategory: $viewModel.activeCategory,
                         counts: categoryCounts)

            // Group list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.filteredGroups) { group in
                        NavigationLink(destination: GroupDetailView(
                            group: group,
                            viewModel: viewModel
                        )) {
                            GroupRowView(group: group)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }

            // Bottom action bar
            HStack {
                Text("\(viewModel.selectedGroupIds.count) groups selected")
                    .foregroundColor(.secondary)
                Spacer()
                Button("Auto Select", action: viewModel.autoSelectGroups)
                Button("Delete (\(formatBytes(selectedSize)))") {
                    viewModel.showCleanupConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(viewModel.selectedGroupIds.isEmpty)
            }
            .padding(16)
        }
        .alert("Move to Trash?", isPresented: $viewModel.showCleanupConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                let manager = CleanupManager()
                Task { await viewModel.removeSelected(using: manager) }
            }
        } message: {
            Text("\(viewModel.selectedGroupIds.count) groups will be moved to Trash.")
        }
        .onAppear {
            // Load groups from appState or scan result
        }
    }

    private var categoryCounts: [DuplicateCategory: Int] {
        Dictionary(grouping: viewModel.groups, by: \.category)
            .mapValues { $0.count }
    }

    private var selectedSize: Int64 {
        viewModel.groups
            .filter { viewModel.selectedGroupIds.contains($0.id) }
            .reduce(0) { $0 + $1.totalSize }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct StatItem: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.headline)
        }
    }
}

struct GroupRowView: View {
    let group: DuplicateGroup
    var body: some View {
        GlassPanel {
            HStack {
                Image(systemName: group.category.iconName)
                    .foregroundColor(group.category.color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(.headline)
                    Text("\(group.files.count) files · \(ByteCountFormatter.string(fromByteCount: group.totalSize, countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(12)
        }
    }
}
