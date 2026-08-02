import SwiftUI
import DesignSystem

struct ResultView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: StoreManager
    @StateObject private var viewModel = ResultViewModel()
    @State private var cleanupFailures: [VaultMoveFailure] = []
    @State private var showPaywall = false
    @State private var paywallReason: String = ""

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
                        NavigationLink(destination: GroupDetailView(group: group)) {
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
                Button(deleteButtonLabel) {
                    attemptCleanup()
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
                runCleanup()
            }
        } message: {
            Text("\(viewModel.selectedGroupIds.count) groups will be moved to Trash. The newest copy of each group is kept.")
        }
        .alert(
            "Some files could not be moved",
            isPresented: Binding(
                get: { !cleanupFailures.isEmpty },
                set: { if !$0 { cleanupFailures = [] } }
            )
        ) {
            Button("OK", role: .cancel) { cleanupFailures = [] }
        } message: {
            Text("\(cleanupFailures.count) file(s) could not be moved to Trash and remain in place.\n\n\(cleanupFailures.map { $0.url.lastPathComponent }.joined(separator: ", "))")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
        }
        .onAppear {
            loadGroups()
        }
    }

    private var deleteButtonLabel: String {
        let bytes = selectedSize
        let base = String(format: NSLocalizedString("Delete (%@)", comment: "Delete selected groups, size in parens"), formatBytes(bytes))
        if !store.isPaidUser, store.freeTierBytesCleaned + bytes > StoreManager.freeCleanupQuotaBytes {
            return base + NSLocalizedString(" · Upgrade", comment: "Upgrade hint appended to delete label")
        }
        return base
    }

    private func attemptCleanup() {
        let bytes = selectedSize
        if store.canCleanup(additionalBytes: bytes) {
            viewModel.showCleanupConfirmation = true
        } else {
            let remaining = max(StoreManager.freeCleanupQuotaBytes - store.freeTierBytesCleaned, 0)
            paywallReason = String(
                format: NSLocalizedString("Cleaning %@ would exceed your %@ free-tier quota (only %@ left).", comment: "Paywall reason"),
                formatBytes(bytes),
                formatBytes(StoreManager.freeCleanupQuotaBytes),
                formatBytes(remaining)
            )
            showPaywall = true
        }
    }

    private func runCleanup() {
        let manager = CleanupManager()
        let bytes = selectedSize
        Task {
            let failures = await viewModel.removeSelected(using: manager)
            if !failures.isEmpty { cleanupFailures = failures }
            // Roll the free-tier counter forward only by the bytes that
            // actually moved to the Trash. Failed URLs are mapped back to
            // their `FileItem.size` so the user isn't penalized for files
            // they couldn't delete (e.g. permission errors). recordFreeTier
            // Cleanup is a no-op once they're paid, so the same call is
            // safe either way and keeps the bookkeeping single-sourced.
            let failedUrls = Set(failures.map(\.url))
            let failedBytes: Int64 = viewModel.groups
                .flatMap(\.files)
                .filter { failedUrls.contains($0.url) }
                .reduce(0) { $0 + $1.size }
            store.recordFreeTierCleanup(bytes: bytes - failedBytes)
        }
    }

    private func loadGroups() {
        if !appState.latestGroups.isEmpty {
            viewModel.loadGroups(appState.latestGroups)
        } else {
            // Deep-link (.results) or navigation without a fresh scan: fall back
            // to the most recent persisted record.
            Task {
                let record = try? await DuplicateRepositoryCoreData().loadScanRecords().first
                if let record, !record.groups.isEmpty {
                    viewModel.loadGroups(record.groups)
                }
            }
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
    let title: LocalizedStringKey
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
                    Text(group.category.displayName)
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