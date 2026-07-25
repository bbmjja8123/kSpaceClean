import SwiftUI
import DesignSystem

struct GroupDetailView: View {
    let group: DuplicateGroup
    @ObservedObject var viewModel: ResultViewModel
    @State private var selectedFileIds: Set<UUID> = []
    @State private var previewUrl: URL?

    var body: some View {
        VStack(spacing: 0) {
            // Group header
            GlassPanel {
                HStack {
                    Image(systemName: group.category.iconName)
                        .font(.title2)
                        .foregroundColor(group.category.color)
                    VStack(alignment: .leading) {
                        Text(group.title).font(.headline)
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
                Button("Move \(selectedFileIds.count) to Trash") {
                    Task { await deleteSelected() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selectedFileIds.isEmpty)
            }
            .padding(16)
        }
    }

    private var selectedSize: Int64 {
        group.files.filter { selectedFileIds.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    private func deleteSelected() async {
        let manager = CleanupManager()
        let filesToDelete = group.files.filter { selectedFileIds.contains($0.id) }
        try? await manager.moveToTrash(filesToDelete)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
