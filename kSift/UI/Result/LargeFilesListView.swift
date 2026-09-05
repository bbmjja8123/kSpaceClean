import SwiftUI
import DesignSystem

/// The Large Files section of the results screen: every file at or above
/// the configured threshold, sortable, multi-selectable, with the same
/// Trash + Vault safety net (and undo) as duplicate cleanup.
struct LargeFilesListView: View {
    let files: [FileItem]
    @EnvironmentObject var store: StoreManager
    @EnvironmentObject var appState: AppState
    @State private var selectedIds: Set<UUID> = []
    @State private var sortOrder: LargeFileSort = .sizeDesc
    @State private var showConfirmation = false
    @State private var showPaywall = false
    @State private var cleanupFailures: [VaultMoveFailure] = []
    @State private var inUseReport: InUseReport?
    @State private var showUndoToast = false
    @State private var cleanedCount = 0
    private let inUseChecker = InUseChecker()

    enum LargeFileSort: String, CaseIterable {
        case sizeDesc, dateDesc, nameAsc

        var label: String {
            switch self {
            case .sizeDesc: return NSLocalizedString("Size (Largest)", comment: "Large-file sort")
            case .dateDesc: return NSLocalizedString("Date (Newest)", comment: "Large-file sort")
            case .nameAsc: return NSLocalizedString("Name (A→Z)", comment: "Large-file sort")
            }
        }
    }

    private var sortedFiles: [FileItem] {
        switch sortOrder {
        case .sizeDesc: return files.sorted { $0.size > $1.size }
        case .dateDesc: return files.sorted { $0.modificationDate > $1.modificationDate }
        case .nameAsc: return files.sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
        }
    }

    private var selectedBytes: Int64 {
        files.filter { selectedIds.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            if files.isEmpty {
                emptyState
            } else {
                // Sort row
                HStack {
                    Text(String(
                        format: NSLocalizedString("%lld files · %@ total", comment: "Large files summary"),
                        files.count,
                        formatBytes(files.reduce(0) { $0 + $1.size })
                    ))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    Spacer()
                    Menu {
                        ForEach(LargeFileSort.allCases, id: \.self) { order in
                            Button(order.label) { sortOrder = order }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(sortOrder.label)
                        }
                        .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

                List(selection: $selectedIds) {
                    ForEach(sortedFiles) { file in
                        FileRowView(file: file, isSelected: selectedIds.contains(file.id))
                            .tag(file.id)
                            .contextMenu {
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                                }
                            }
                    }
                }

                // Bottom action bar
                HStack {
                    Text(String(
                        format: NSLocalizedString("%lld selected · %@", comment: "Large files selection summary"),
                        selectedIds.count,
                        formatBytes(selectedBytes)
                    ))
                    .foregroundColor(.secondary)
                    Spacer()
                    Button(deleteButtonLabel) {
                        attemptCleanup()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(selectedIds.isEmpty)
                }
                .padding(16)
            }
        }
        .alert("Move to Trash?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteSelected() }
            }
        } message: {
            Text(String(
                format: NSLocalizedString("%lld file(s) will be moved to Trash and kept in the vault for 30 days.", comment: "Large files cleanup confirmation"),
                selectedIds.count
            ))
        }
        .alert(
            InUsePrompt.title(inUseReport ?? InUseReport()),
            isPresented: Binding(
                get: { inUseReport != nil },
                set: { if !$0 { inUseReport = nil } }
            )
        ) {
            Button(NSLocalizedString("Skip in-use files", comment: "In-use prompt — clean everything else")) {
                if let report = inUseReport {
                    let skip = Set(InUsePrompt.filesToSkip(report))
                    selectedIds = Set(files.filter { selectedIds.contains($0.id) && !skip.contains($0.url) }.map(\.id))
                }
                inUseReport = nil
                if !selectedIds.isEmpty {
                    showConfirmation = true
                }
            }
            Button(NSLocalizedString("Move anyway", comment: "In-use prompt — clean everything including open files"), role: .destructive) {
                inUseReport = nil
                Task { await deleteSelected() }
            }
            Button("Cancel", role: .cancel) { inUseReport = nil }
        } message: {
            Text(InUsePrompt.message(inUseReport ?? InUseReport()))
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
        .toast(isPresented: $showUndoToast, autoDismissAfter: 8) {
            ToastView(
                title: NSLocalizedString("Moved to Vault", comment: "Cleanup success title"),
                subtitle: String(
                    format: NSLocalizedString("%lld file(s) moved to Trash. Kept 30 days in the vault.", comment: "Cleanup success subtitle"),
                    cleanedCount
                ),
                icon: "checkmark.circle.fill",
                actionTitle: NSLocalizedString("Undo", comment: "Undo cleanup action"),
                onAction: {
                    appState.undoLastCleanup()
                    selectedIds.removeAll()
                },
                onDismiss: { showUndoToast = false }
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "externaldrive.badge.timemachine",
            title: NSLocalizedString("No large files in this scan", comment: "Large files empty title"),
            subtitle: NSLocalizedString(
                "Files at or above the threshold in Settings appear here after a scan.",
                comment: "Large files empty subtitle"
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deleteButtonLabel: String {
        let base = String(
            format: NSLocalizedString("Move %lld to Trash", comment: "Move selected files to Trash"),
            selectedIds.count
        )
        if !store.isPaidUser,
           store.freeTierBytesCleaned + selectedBytes > StoreManager.freeCleanupQuotaBytes {
            return base + NSLocalizedString(" · Upgrade", comment: "Upgrade hint appended to delete label")
        }
        return base
    }

    private func attemptCleanup() {
        if store.canCleanup(additionalBytes: selectedBytes) {
            Task {
                let staged = files.filter { selectedIds.contains($0.id) }
                let report = await inUseChecker.assess(staged)
                if report.isEmpty {
                    showConfirmation = true
                } else {
                    inUseReport = report
                }
            }
        } else {
            showPaywall = true
        }
    }

    private func deleteSelected() async {
        let toDelete = files.filter { selectedIds.contains($0.id) }
        guard !toDelete.isEmpty else { return }
        let manager = CleanupManager()
        do {
            let result = try await manager.moveToTrash(toDelete)
            appState.lastCleanupSession = result.session
            // Remove successes from the visible list.
            let failedURLs = Set(result.failures.map(\.url))
            let removed = Set(toDelete.map(\.url)).subtracting(failedURLs)
            appState.latestLargeFiles = files.filter { !removed.contains($0.url) }
            let removedBytes = toDelete.filter { removed.contains($0.url) }.reduce(0) { $0 + $1.size }
            store.recordFreeTierCleanup(bytes: removedBytes)
            cleanedCount = removed.count
            selectedIds.removeAll()
            if !result.failures.isEmpty {
                cleanupFailures = result.failures
            }
            if removed.count > 0 {
                showUndoToast = true
            }
        } catch {
            cleanupFailures = [VaultMoveFailure(
                url: toDelete[0].url,
                reason: error.localizedDescription
            )]
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
