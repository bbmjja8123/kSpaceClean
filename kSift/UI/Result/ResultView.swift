import SwiftUI
import DesignSystem

struct ResultView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: StoreManager
    @StateObject private var viewModel = ResultViewModel()
    @State private var cleanupFailures: [VaultMoveFailure] = []
    @State private var cleanupSuccessCount: Int = 0
    @State private var showCleanupSuccess: Bool = false
    @State private var showPaywall = false
    @State private var paywallReason: String = ""
    @State private var showAdvancedFilters: Bool = false
    @FocusState private var searchFocused: Bool

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
                    .help(NSLocalizedString(
                        "Start a new scan (⌘N)",
                        comment: "Tooltip for Command-N new-scan shortcut"
                    ))
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Category breakdown
            if !viewModel.groups.isEmpty {
                CategoryBreakdownBar(groups: viewModel.groups)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            // Filter bar
            FilterBarView(activeCategory: $viewModel.activeCategory,
                         counts: viewModel.categoryCounts)

            // P1-1: collapsible advanced filter chips (size range + date
            // range). Toggled via a small "More filters" / "Less filters"
            // button so the default result page stays visually quiet.
            HStack {
                Button {
                    showAdvancedFilters.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showAdvancedFilters
                              ? "chevron.up"
                              : "slider.horizontal.3")
                        Text(showAdvancedFilters
                             ? NSLocalizedString("Less filters", comment: "Collapse advanced filters")
                             : NSLocalizedString("More filters", comment: "Expand advanced filters"))
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderless)
                if showAdvancedFilters || viewModel.hasActiveFilters {
                    Text(activeFiltersSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            if showAdvancedFilters {
                FilterChipsView(
                    minSize: $viewModel.minSize,
                    maxSize: $viewModel.maxSize,
                    dateFrom: $viewModel.dateFrom,
                    dateTo: $viewModel.dateTo,
                    onReset: { viewModel.resetFilters() }
                )
            }

            // Search field (⌘F to focus). Sits above the sort row so the
            // filter→sort→results hierarchy stays intact.
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField(
                    String(localized: "Search filename…", defaultValue: "Search filename…"),
                    text: $viewModel.searchText
                )
                .textFieldStyle(.plain)
                .focused($searchFocused)
                if !viewModel.searchText.isEmpty {
                    Button { viewModel.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            .keyboardShortcut("f", modifiers: .command)

            // Sort row (sits under the filter bar so it doesn't compete with
            // the primary selection/count chips for attention).
            HStack {
                Spacer()
                Menu {
                    ForEach(ResultViewModel.SortOrder.allCases, id: \.self) { order in
                        Button {
                            viewModel.sortOrder = order
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if viewModel.sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(viewModel.sortOrder.rawValue)
                    }
                    .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            // Group list
            if viewModel.filteredGroups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.filteredGroups) { group in
                            NavigationLink(destination: GroupDetailView(group: group)) {
                                GroupRowView(
                                    group: group,
                                    sameNameSiblingCount: viewModel.sameNameCounts[group.files.first?.url.lastPathComponent ?? ""] ?? 0
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }

            // Bottom action bar
            HStack {
                Text("\(viewModel.selectedGroupIds.count) groups selected")
                    .foregroundColor(.secondary)
                Spacer()
                Button("Auto Select", action: viewModel.autoSelectGroups)
                    .help(NSLocalizedString(
                        "Select all groups (⌘A)",
                        comment: "Tooltip for Command-A select-all shortcut"
                    ))
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
        .alert(
            NSLocalizedString("Moved to Vault", comment: "Cleanup success title"),
            isPresented: $showCleanupSuccess
        ) {
            Button(NSLocalizedString("Open Vault", comment: "Open vault after cleanup")) {
                showCleanupSuccess = false
                appState.navigation = .vault
            }
            Button(NSLocalizedString("Done", comment: "Dismiss cleanup success"), role: .cancel) {
                showCleanupSuccess = false
            }
        } message: {
            Text(String(format: NSLocalizedString("%lld file(s) were moved to Trash and safely stored in the vault for 30 days.", comment: "Cleanup success message"),
                        cleanupSuccessCount))
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
        }
        .onAppear {
            loadGroups()
        }
        // Hidden keyboard-shortcut buttons so ⌘A / ⌘N / Esc work whether or
        // not the on-screen action buttons are visible (e.g. in the empty
        // state). `.frame(0)` keeps the layout intact while still exposing
        // the shortcut to SwiftUI's menu/keyboard routing.
        .background {
            Group {
                // ⌘A — select every group (same as tapping "Auto Select")
                Button("Select All") {
                    viewModel.autoSelectGroups()
                }
                .keyboardShortcut("a", modifiers: .command)
                .help(NSLocalizedString(
                    "Select all groups (⌘A)",
                    comment: "Tooltip for Command-A select-all shortcut"
                ))
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)

                // ⌘N — jump to the scan page to start a fresh scan
                Button("New Scan") {
                    appState.navigation = .scan
                }
                .keyboardShortcut("n", modifiers: .command)
                .help(NSLocalizedString(
                    "Start a new scan (⌘N)",
                    comment: "Tooltip for Command-N new-scan shortcut"
                ))
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)

                // Esc — clear current selection. macOS 14+ routes the key
                // press through `onKeyPress`; older macOS still gets the
                // shortcut via SwiftUI's command set so both paths work.
                Button("Clear Selection") {
                    viewModel.clearSelection()
                }
                .keyboardShortcut(.cancelAction)
                .help(NSLocalizedString(
                    "Clear selection (Esc)",
                    comment: "Tooltip for Escape clear-selection shortcut"
                ))
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            }
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
            let succeeded = bytes - failedBytes
            store.recordFreeTierCleanup(bytes: succeeded)
            // Surface cleanup success so the user can jump straight to the
            // Vault. Only show when at least one file actually moved.
            if succeeded > 0 {
                cleanupSuccessCount = viewModel.selectedGroupIds.count
                showCleanupSuccess = true
            }
        }
    }

    private func loadGroups() {
        if !appState.latestGroups.isEmpty {
            viewModel.loadGroups(appState.latestGroups)
        } else {
            // Deep-link (.results) or navigation without a fresh scan: fall back
            // to the most recent persisted record. Repository uses
            // PersistenceController.shared by default; run the load detached so
            // it doesn't pay MainActor hop cost before crossing the actor.
            Task.detached(priority: .userInitiated) {
                let record = try? await DuplicateRepositoryCoreData().loadScanRecords().first
                if let record, !record.groups.isEmpty {
                    await MainActor.run {
                        viewModel.loadGroups(record.groups)
                    }
                }
            }
        }
    }

    private var selectedSize: Int64 {
        viewModel.groups
            .filter { viewModel.selectedGroupIds.contains($0.id) }
            .reduce(0) { $0 + $1.totalSize }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Short human-readable summary of currently active filter bounds
    /// ("1 MB – 10 GB · 2024-01-01 – now"). Used as a chip next to the
    /// expand toggle so users can see what's filtering their results
    /// without opening the panel.
    private var activeFiltersSummary: String {
        var parts: [String] = []
        if viewModel.minSize > 0 || viewModel.maxSize < Int64.max {
            let lo = viewModel.minSize > 0
                ? ByteCountFormatter.string(fromByteCount: viewModel.minSize, countStyle: .file)
                : NSLocalizedString("Any", comment: "Unbounded filter bound")
            let hi = viewModel.maxSize < Int64.max
                ? ByteCountFormatter.string(fromByteCount: viewModel.maxSize, countStyle: .file)
                : NSLocalizedString("Any", comment: "Unbounded filter bound")
            parts.append("\(lo) – \(hi)")
        }
        if viewModel.dateFrom != nil || viewModel.dateTo != nil {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            let from = viewModel.dateFrom.map { formatter.string(from: $0) }
                ?? NSLocalizedString("Any", comment: "Unbounded filter bound")
            let to = viewModel.dateTo.map { formatter.string(from: $0) }
                ?? NSLocalizedString("Any", comment: "Unbounded filter bound")
            parts.append("\(from) – \(to)")
        }
        return parts.joined(separator: " · ")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: viewModel.searchText.isEmpty ? "sparkles" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.success)
            Text(viewModel.searchText.isEmpty
                 ? NSLocalizedString("No duplicates in this scan", comment: "Empty result body title")
                 : NSLocalizedString("No matches", comment: "Empty search body title"))
                .font(.title3).bold()
            Text(viewModel.searchText.isEmpty
                 ? NSLocalizedString("Try a different folder or enable more detectors in Settings.", comment: "Empty result body subtitle")
                 : NSLocalizedString("Try a different filename or clear the search.", comment: "Empty search body subtitle"))
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 360)
            Button(NSLocalizedString("Back to scan", comment: "Empty state CTA")) {
                appState.navigation = .scan
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
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
    /// How many sibling groups share the same first-file name. > 1 means this
    /// row is part of a same-name cluster (e.g. "IMG_1234.jpg" duplicated
    /// across 3 different folders). Computed upstream so the row stays O(1).
    var sameNameSiblingCount: Int = 0
    /// Total count of APFS-clone-tagged files in the group. 0 means no
    /// clones; > 0 surfaces a "N clones" badge so the user knows freeing
    /// them is essentially free (no real disk reclaimed).
    private var cloneCount: Int {
        group.files.filter(\.isAPFSClone).count
    }

    var body: some View {
        GlassPanel {
            HStack {
                Image(systemName: group.category.iconName)
                    .foregroundColor(group.category.color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.category.displayName)
                            .font(.headline)
                        // Same-name cluster badge: "×N" tells the user that
                        // another group elsewhere also starts with this name,
                        // so the cleanup buttons will collapse them together.
                        if sameNameSiblingCount > 1 {
                            Text("×\(sameNameSiblingCount)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundColor(.accentColor)
                                .clipShape(Capsule())
                                .help(String.localizedStringWithFormat(
                                    NSLocalizedString(
                                        "This group shares the same name with %d other groups",
                                        comment: "Same-name cluster tooltip"
                                    ),
                                    sameNameSiblingCount
                                ))
                        }
                        // APFS-clone badge: lets the user know these files
                        // share physical blocks; cleaning them only frees
                        // logical size, not on-disk blocks.
                        if cloneCount > 0 {
                            Label("\(cloneCount)", systemImage: "bolt.horizontal.fill")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .clipShape(Capsule())
                                .help(NSLocalizedString(
                                    "APFS clones share physical blocks — cleaning frees logical size only",
                                    comment: "APFS clone tooltip"
                                ))
                        }
                    }
                    Text("\(group.files.count) files · \(ByteCountFormatter.string(fromByteCount: group.totalSize, countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                // Visual categories get an inline thumbnail strip so users
                // can confirm "yes, these are duplicates" without opening
                // the detail view. Non-visual categories stay text-only.
                if showsThumbnailStrip {
                    ThumbnailStrip(files: group.files)
                        .frame(maxWidth: 200, alignment: .trailing)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(12)
        }
    }

    /// True for categories whose duplicates benefit from a quick visual
    /// confirmation in the row. Identical byte matches are also shown —
    /// filenames + sizes usually disambiguate, but a thumbnail strip
    /// makes the "are these really the same image?" question answerable
    /// in-place for the perceptual category.
    private var showsThumbnailStrip: Bool {
        switch group.category {
        case .perceptual, .directoryDedup, .identical:
            return true
        case .largeFile, .buildArtifact, .rawJPEG:
            return false
        }
    }
}