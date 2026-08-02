import SwiftUI
import DesignSystem

struct GroupDetailView: View {
    let group: DuplicateGroup
    @EnvironmentObject var store: StoreManager
    @State private var selectedFileIds: Set<UUID> = []
    @State private var previewUrl: URL?
    @State private var showPaywall = false
    @State private var showConfirmation = false

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

            // Auto-Select button
            HStack {
                Button("Auto Keep Newest (\(group.files.count - 1) to delete)") {
                    let sorted = group.files.sorted { $0.modificationDate > $1.modificationDate }
                    if let newest = sorted.first {
                        selectedFileIds = Set(group.files.filter { $0.id != newest.id }.map(\.id))
                    }
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .padding(.horizontal, 16)

            // File list
            List(selection: $selectedFileIds) {
                ForEach(group.files) { file in
                    FileRowView(file: file, isSelected: selectedFileIds.contains(file.id))
                        .tag(file.id)
                        .onTapGesture(count: 2) { previewUrl = file.url }
                        .contextMenu {
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([file.url])
                            }
                            Button("QuickLook") { previewUrl = file.url }
                        }
                }
            }

            // Bottom bar
            HStack {
                Text("\(selectedFileIds.count) selected · \(formatBytes(selectedSize))")
                Spacer()
                Button(deleteButtonLabel) {
                    attemptCleanup()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selectedFileIds.isEmpty)
            }
            .padding(16)
        }
        .alert("Move to Trash?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteSelected() }
            }
        } message: {
            Text("\(selectedFileIds.count) file(s) will be moved to Trash. The newest copy of the group is kept.")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
        }
    }

    private var deleteButtonLabel: String {
        let base = String(format: NSLocalizedString("Move %lld to Trash", comment: "Move selected files to Trash"), selectedFileIds.count)
        if !store.isPaidUser,
           store.freeTierBytesCleaned + selectedSize > StoreManager.freeCleanupQuotaBytes {
            return base + NSLocalizedString(" · Upgrade", comment: "Upgrade hint appended to delete label")
        }
        return base
    }

    private var selectedSize: Int64 {
        group.files.filter { selectedFileIds.contains($0.id) }.reduce(0) { $0 + $1.size }
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
        let manager = CleanupManager()
        let filesToDelete = group.files.filter { selectedFileIds.contains($0.id) }
        let bytes = filesToDelete.reduce(Int64(0)) { $0 + $1.size }
        do {
            try await manager.moveToTrash(filesToDelete)
            store.recordFreeTierCleanup(bytes: bytes)
        } catch {
            // Manager surfaces failures as exceptions; the user already saw
            // the confirmation alert, so just log and let them re-attempt.
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}