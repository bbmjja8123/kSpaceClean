import SwiftUI
import DesignSystem
// `.quickLookPreview` lives in Apple's `_QuickLook_SwiftUI` module (exposed
// since macOS 11, despite older docs saying 14). Neither SwiftUI nor
// QuickLookUI re-exports it, so import the backing module directly.
import _QuickLook_SwiftUI

struct GroupDetailView: View {
    let group: DuplicateGroup
    /// The shared results view model. Nil when opened from a history
    /// record — in that case file selection lives locally and cleanup
    /// failures surface through the same alert path.
    weak var viewModel: ResultViewModel?
    @EnvironmentObject var store: StoreManager
    @State private var localSelectedFileIds: Set<UUID> = []
    @State private var localPlan: SelectionPlan?
    @State private var showPaywall = false
    @State private var showConfirmation = false
    @State private var cleanupFailures: [VaultMoveFailure] = []
    @State private var fileSort: FileSortOrder = .dateDesc
    @State private var quickLookURL: URL?

    enum FileSortOrder {
        case dateDesc, dateAsc, sizeDesc, sizeAsc, pathAsc

        var label: String {
            switch self {
            case .dateDesc: return NSLocalizedString("Date", comment: "Sort by date (newest first)")
            case .dateAsc: return NSLocalizedString("Date (Oldest)", comment: "Sort by date (oldest first)")
            case .sizeDesc: return NSLocalizedString("Size (Largest)", comment: "Sort by size (largest first)")
            case .sizeAsc: return NSLocalizedString("Size (Smallest)", comment: "Sort by size (smallest first)")
            case .pathAsc: return NSLocalizedString("Path (A→Z)", comment: "Sort by path A to Z")
            }
        }
    }

    /// File selection: shared with the results list when a view model is
    /// available (so group↔detail selection always agrees), otherwise local.
    private var selectedFileIds: Binding<Set<UUID>> {
        if let viewModel {
            return Binding(
                get: { viewModel.fileSelections[group.id] ?? [] },
                set: { viewModel.setFileSelection(groupId: group.id, fileIds: $0) }
            )
        }
        return Binding(
            get: { localSelectedFileIds },
            set: { localSelectedFileIds = $0 }
        )
    }

    /// The explainable plan backing this group, if one exists.
    private var activePlan: SelectionPlan? {
        viewModel?.selectionPlans[group.id] ?? localPlan
    }

    private var sortedFiles: [FileItem] {
        switch fileSort {
        case .dateDesc: return group.files.sorted { $0.modificationDate > $1.modificationDate }
        case .dateAsc: return group.files.sorted { $0.modificationDate < $1.modificationDate }
        case .sizeDesc: return group.files.sorted { $0.size > $1.size }
        case .sizeAsc: return group.files.sorted { $0.size < $1.size }
        case .pathAsc: return group.files.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Group header
            GlassPanel {
                HStack {
                    Image(systemName: group.category.iconName)
                        .font(.title2)
                        .foregroundColor(group.category.color)
                    VStack(alignment: .leading) {
                        Text(group.category.displayName).font(.headline)
                        Text("\(group.files.count) files · \(formatBytes(group.totalSize))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
            }
            .padding(8)

            // Perceptual groups get an inline thumbnail strip so the user can
            // see which photos are similar at a glance without opening each one.
            if group.category == .perceptual {
                ThumbnailStrip(files: group.files, size: 80, maxVisible: 12)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            // Smart Select: pick which copy to keep with a visible strategy,
            // then see the reason badges next to each row.
            HStack {
                strategyMenu
                Spacer()
                // In-group sort: lets the user cluster files by date, size, or
                // path within a single group (e.g., to find the biggest copy).
                Menu {
                    Button("Date (Newest first)") { fileSort = .dateDesc }
                    Button("Date (Oldest first)") { fileSort = .dateAsc }
                    Button("Size (Largest first)") { fileSort = .sizeDesc }
                    Button("Size (Smallest first)") { fileSort = .sizeAsc }
                    Button("Path (A→Z)") { fileSort = .pathAsc }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(fileSort.label)
                    }
                    .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 16)

            // File list
            List(selection: selectedFileIds) {
                ForEach(sortedFiles) { file in
                    FileRowView(
                        file: file,
                        isSelected: selectedFileIds.wrappedValue.contains(file.id),
                        reason: activePlan?.reasons[file.id]
                    )
                    .tag(file.id)
                    .contextMenu {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([file.url])
                        }
                        Button("QuickLook") { quickLookURL = file.url }
                    }
                }
            }

            // Bottom bar
            HStack {
                Text("\(selectedFileIds.wrappedValue.count) selected · \(formatBytes(selectedSize))")
                Spacer()
                Button(deleteButtonLabel) {
                    attemptCleanup()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selectedFileIds.wrappedValue.isEmpty)
            }
            .padding(16)
        }
        .alert("Move to Trash?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteSelected() }
            }
        } message: {
            Text("\(selectedFileIds.wrappedValue.count) file(s) will be moved to Trash and kept in the vault for 30 days.")
        }
        .alert(
            NSLocalizedString("Some files could not be moved", comment: "Cleanup failure alert title"),
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
        // Real QuickLook on macOS 14+; LaunchServices open as the macOS 13
        // fallback (the SDK on this toolchain exposes .quickLookPreview).
        .modifier(QuickLookModifier(url: $quickLookURL))
        // Keyboard shortcuts: Space opens QuickLook for the selected file;
        // Esc clears the file selection.
        .background {
            Group {
                Button("QuickLook Selected") {
                    if let file = group.files.first(where: { selectedFileIds.wrappedValue.contains($0.id) }) {
                        quickLookURL = file.url
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
                .help(NSLocalizedString(
                    "QuickLook selected file (Space)",
                    comment: "Tooltip for Space QuickLook shortcut"
                ))
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)

                Button("Clear Selection") {
                    selectedFileIds.wrappedValue.removeAll()
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

    /// Applies a keep-strategy to this group only: the winning copy gets a
    /// reason badge, every other copy is staged for removal.
    private var strategyMenu: some View {
        Menu {
            ForEach(SelectionStrategy.allCases, id: \.self) { strategy in
                Button {
                    apply(strategy: strategy)
                } label: {
                    Text(strategy.title)
                }
                .help(strategy.help)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "wand.and.stars")
                Text(NSLocalizedString("Auto Keep", comment: "Auto Keep strategy menu label"))
            }
            .font(.callout)
        }
        .help(NSLocalizedString("Automatically keep one copy — the reason is shown next to each file", comment: "Auto Keep tooltip"))
    }

    private func apply(strategy: SelectionStrategy) {
        let plan = SelectionPlanner.plan(for: group, strategy: strategy)
        if let viewModel {
            // Stage through the shared model so the parent list selection
            // stays in sync with what the detail view shows.
            if !viewModel.selectedGroupIds.contains(group.id) {
                viewModel.toggleGroup(group.id)
            }
            viewModel.setPlan(plan, for: group.id)
        } else {
            localPlan = plan
            localSelectedFileIds = Set(plan.remove.map(\.id))
        }
    }

    private var deleteButtonLabel: String {
        let base = String(format: NSLocalizedString("Move %lld to Trash", comment: "Move selected files to Trash"), selectedFileIds.wrappedValue.count)
        if !store.isPaidUser,
           store.freeTierBytesCleaned + selectedSize > StoreManager.freeCleanupQuotaBytes {
            return base + NSLocalizedString(" · Upgrade", comment: "Upgrade hint appended to delete label")
        }
        return base
    }

    private var selectedSize: Int64 {
        group.files.filter { selectedFileIds.wrappedValue.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    private func attemptCleanup() {
        let bytes = selectedSize
        if store.canCleanup(additionalBytes: bytes) {
            showConfirmation = true
        } else {
            showPaywall = true
        }
    }

    private func deleteSelected() async {
        let failures: [VaultMoveFailure]
        if let viewModel {
            failures = await viewModel.removeFiles(group: group, using: CleanupManager())
        } else {
            let manager = CleanupManager()
            let filesToDelete = group.files.filter { localSelectedFileIds.contains($0.id) }
            do {
                let result = try await manager.moveToTrash(filesToDelete)
                failures = result.failures
            } catch {
                failures = [VaultMoveFailure(
                    url: filesToDelete.first?.url ?? URL(fileURLWithPath: "/"),
                    reason: error.localizedDescription
                )]
            }
        }
        // Failures are surfaced (previously this path swallowed errors so a
        // failed cleanup looked like a successful one).
        if !failures.isEmpty {
            cleanupFailures = failures
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Real system QuickLook sheet — `.quickLookPreview` is available from
/// macOS 11 via `_QuickLook_SwiftUI`, so no #available gating is needed.
struct QuickLookModifier: ViewModifier {
    @Binding var url: URL?

    func body(content: Content) -> some View {
        content.quickLookPreview($url)
    }
}
