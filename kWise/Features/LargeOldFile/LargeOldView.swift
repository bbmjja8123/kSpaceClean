import SwiftUI
import DesignSystem
import CommonUtils

/// Main view for large/old file scanning and cleanup.
struct LargeOldView: View {
    @StateObject private var viewModel = LargeOldViewModel()
    @State private var showFolderPicker = false
    @State private var sizePreset: SizePreset = .mb50
    @State private var agePreset: Int = 0

    enum SizePreset: Int, CaseIterable, Identifiable {
        case mb50 = 50
        case mb100 = 100
        case mb500 = 500
        case gb1 = 1024

        var id: Int { rawValue }
        var label: String {
            switch self {
            case .mb50: return "50 MB"
            case .mb100: return "100 MB"
            case .mb500: return "500 MB"
            case .gb1: return "1 GB"
            }
        }
        var bytes: Int64 { Int64(rawValue) * 1024 * 1024 }
    }

    var body: some View {
        VStack(spacing: 0) {
            configBar
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)

            if viewModel.entries.isEmpty, !viewModel.isScanning {
                emptyState
            } else {
                contentArea
            }
        }
    }

    // MARK: - Config Bar

    private var configBar: some View {
        HStack(spacing: AppSpacing.md) {
            // Path
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "folder")
                    .foregroundColor(.textSecondary)
                    .font(.system(size: 12))
                Text(shortenedPath)
                    .font(AppFont.callout)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: 200, alignment: .leading)

            Button("Choose…") { showFolderPicker = true }
                .buttonStyle(.borderless)
                .font(AppFont.callout)
                .foregroundColor(.brandPrimary)
                .background {
                    FolderPicker(isPresented: $showFolderPicker) { urls in
                        if !urls.isEmpty { viewModel.config.scanPaths = urls }
                    }
                }

            Divider().frame(height: 18)

            // Min size picker
            Picker("Min", selection: $sizePreset) {
                ForEach(SizePreset.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 110)
            .onChange(of: sizePreset) { new in
                viewModel.config.minFileSize = new.bytes
            }

            // Age filter
            Picker("Age", selection: $agePreset) {
                Text("Any").tag(0)
                Text("30+ days").tag(30)
                Text("90+ days").tag(90)
                Text("180+ days").tag(180)
            }
            .pickerStyle(.menu)
            .frame(width: 130)
            .onChange(of: agePreset) { new in
                viewModel.config.minFileAge = new == 0 ? nil : TimeInterval(new) * 86400
            }

            Spacer()

            // Scan / cancel
            if viewModel.isScanning {
                HStack(spacing: AppSpacing.sm) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Button("Cancel") { viewModel.cancelScan() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.danger)
                }
            } else {
                Button("Scan") { viewModel.startScan() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.brandPrimary)
            }
        }
    }

    private var shortenedPath: String {
        guard let first = viewModel.config.scanPaths.first else { return "—" }
        if viewModel.config.scanPaths.count == 1 {
            return first.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }
        return "\(first.lastPathComponent) +\(viewModel.config.scanPaths.count - 1)"
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "doc.circle",
            title: "Find Large & Old Files",
            subtitle: "Scan a folder to find files above the size threshold and reclaim disk space."
        )
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(spacing: 0) {
            sortingBar
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.entries) { entry in
                        fileRow(entry)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.sm)
            }

            summaryBar
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
        }
    }

    // MARK: - Sorting Bar

    private var sortingBar: some View {
        HStack(spacing: AppSpacing.md) {
            sortButton(.size, label: "Size")
            sortButton(.date, label: "Modified")
            sortButton(.name, label: "Name")
            sortButton(.path, label: "Path")
            Spacer()
            Text("\(viewModel.entries.count) files")
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
        }
    }

    private func sortButton(_ field: LargeOldSortField, label: String) -> some View {
        let isActive = viewModel.sortBy == field
        return Button {
            viewModel.toggleSort(field)
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(AppFont.caption)
                    .fontWeight(isActive ? .semibold : .regular)
                if isActive {
                    Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundColor(isActive ? .brandPrimary : .textSecondary)
        }
        .buttonStyle(.borderless)
    }

    // MARK: - File Row

    private func fileRow(_ entry: LargeOldFileEntry) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Toggle(isOn: Binding(
                get: { entry.isSelected },
                set: { _ in viewModel.toggleSelection(entry.id) }
            )) { }
                .toggleStyle(.checkbox)
                .controlSize(.small)

            Image(systemName: icon(for: entry.url))
                .foregroundColor(.textPrimary)
                .font(.system(size: 14))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.fileName)
                    .font(AppFont.callout)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Text(abbreviatePath(entry.path))
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(entry.modificationDate, style: .date)
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
                .frame(minWidth: 80, alignment: .trailing)

            Text(FileSizeFormatter.abbreviated(from: entry.size))
                .font(AppFont.monoDigit)
                .foregroundColor(.textPrimary)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, AppSpacing.sm)
        .background(entry.isSelected ? Color.brandPrimary.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                statLabel("Total", value: FileSizeFormatter.abbreviated(from: viewModel.totalSize))
                Divider().frame(height: 16)
                statLabel("Selected", value: "\(viewModel.selectedEntries.count)")
                statLabel("Size", value: FileSizeFormatter.abbreviated(from: viewModel.selectedSize))
            }
            Spacer()
            HStack(spacing: AppSpacing.sm) {
                Button("Select All") { viewModel.selectAll() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Deselect") { viewModel.deselectAll() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Clean (\(viewModel.selectedEntries.count))") {
                    Task { _ = await viewModel.cleanupSelected() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.danger)
                .disabled(viewModel.selectedEntries.isEmpty)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl))
    }

    // MARK: - Helpers

    private func statLabel(_ title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
            Text(value)
                .font(AppFont.monoDigit)
                .foregroundColor(.textPrimary)
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func icon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif":
            return "photo"
        case "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm":
            return "video"
        case "mp3", "wav", "aac", "flac", "m4a", "ogg", "wma":
            return "music.note"
        case "pdf": return "doc.richtext"
        case "doc", "docx", "rtf", "pages": return "doc.text"
        case "xls", "xlsx", "csv", "numbers": return "tablecells"
        case "zip", "tar", "gz", "bz2", "7z", "rar", "zst": return "archivebox"
        case "app", "dmg", "pkg": return "app"
        case "swift", "js", "ts", "py", "go", "rs", "cpp", "c", "h", "java", "kt":
            return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }
}

// MARK: - Folder Picker (AppKit bridge)

private struct FolderPicker: NSViewRepresentable {
    @Binding var isPresented: Bool
    let onCompletion: ([URL]) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard isPresented, let window = nsView.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.message = "Select folders to scan"
        panel.prompt = "Select"
        panel.beginSheetModal(for: window) { response in
            isPresented = false
            if response == .OK { onCompletion(panel.urls) }
        }
    }
}

#if DEBUG
struct LargeOldView_Previews: PreviewProvider {
    static var previews: some View {
        LargeOldView()
            .frame(width: 800, height: 600)
    }
}
#endif