import SwiftUI
import DesignSystem

struct GroupDetailView: View {
    let group: DuplicateGroup
    @EnvironmentObject var store: StoreManager
    @State private var selectedFileIds: Set<UUID> = []
    @State private var previewUrl: URL?
    @State private var showPaywall = false
    @State private var showConfirmation = false
    @State private var fileSort: FileSortOrder = .dateDesc

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

    private var sortedFiles: [FileItem] {
        switch fileSort {
        case .dateDesc: return group.files.sorted { $0.modificationDate > $1.modificationDate }
        case .dateAsc: return group.files.sorted { $0.modificationDate < $1.modificationDate }
        case .sizeDesc: return group.files.sorted { $0.size > $1.size }
        case .sizeAsc: return group.files.sorted { $0.size < $1.size }
        case .pathAsc: return group.files.sorted { $0.url.path < $1.url.path }
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
                ThumbnailStrip(files: group.files)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

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
            List(selection: $selectedFileIds) {
                ForEach(sortedFiles) { file in
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

/// Horizontal scrolling thumbnail strip for perceptual groups. Caps at 12
/// thumbnails to keep the strip readable; overflow is rendered as a "+N" tile.
private struct ThumbnailStrip: View {
    let files: [FileItem]
    private static let maxVisible = 12

    var body: some View {
        let visible = Array(files.prefix(Self.maxVisible))
        let overflow = files.count - visible.count
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visible) { file in
                    ThumbnailView(url: file.url, size: 80)
                }
                if overflow > 0 {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppRadius.sm)
                            .fill(Color.secondary.opacity(0.15))
                        Text(String(format: NSLocalizedString("+%lld", comment: "More thumbnails overflow"), overflow))
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 80, height: 80)
                }
            }
        }
    }
}