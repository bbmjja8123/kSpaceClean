import SwiftUI
import DesignSystem
import CommonUtils

/// Main view for duplicate file detection and cleanup.
struct DuplicateView: View {
    @ObservedObject var viewModel: DuplicateViewModel
    @State private var showFolderPicker = false

    var body: some View {
        VStack(spacing: 0) {
            configBar
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)

            if viewModel.groups.isEmpty, !viewModel.isScanning {
                emptyState
            } else {
                contentArea
            }
        }
    }

    // MARK: - Config Bar

    private var configBar: some View {
        HStack(spacing: AppSpacing.md) {
            // Path display
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
            .frame(maxWidth: 180, alignment: .leading)

            Button("Choose...") {
                showFolderPicker = true
            }
            .buttonStyle(.borderless)
            .font(AppFont.callout)
            .foregroundColor(.brandPrimary)
            .background {
                FolderPickerView(isPresented: $showFolderPicker) { urls in
                    if !urls.isEmpty {
                        viewModel.scanPaths = urls
                    }
                }
            }

            Spacer()

            // Scan / Cancel button
            if viewModel.isScanning {
                HStack(spacing: AppSpacing.sm) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Button("Cancel") {
                        viewModel.cancelScan()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.danger)
                }
            } else {
                Button("Scan") {
                    viewModel.startScan()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.brandPrimary)
            }
        }
    }

    private var shortenedPath: String {
        guard let first = viewModel.scanPaths.first else { return "—" }
        if viewModel.scanPaths.count == 1 {
            return first.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }
        return "\(first.lastPathComponent) +\(viewModel.scanPaths.count - 1)"
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "doc.on.doc",
            title: "Find Duplicate Files",
            subtitle: "Scan folders to find identical files and reclaim wasted space."
        )
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(spacing: 0) {
            // Progress bar during scan
            if viewModel.isScanning {
                scanningProgress
            }

            // Groups list
            ScrollView {
                LazyVStack(spacing: AppSpacing.sm) {
                    ForEach($viewModel.groups) { $group in
                        groupSection($group)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
            }

            // Summary bar
            summaryBar
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
        }
    }

    // MARK: - Scanning Progress

    private var scanningProgress: some View {
        VStack(spacing: AppSpacing.xs) {
            ProgressView(value: viewModel.scanProgress)
                .progressViewStyle(.linear)
                .tint(.brandPrimary)

            HStack {
                Text("Scanning...")
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
                Spacer()
                Text(FileSizeFormatter.abbreviated(from: viewModel.totalWasted))
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .background(Color.bgSecondary.opacity(0.5))
    }

    // MARK: - Group Section

    private func groupSection(_ group: Binding<DuplicateGroup>) -> some View {
        GlassPanel {
            VStack(spacing: 0) {
                // Header
                groupHeader(group)

                // Expanded files
                if group.wrappedValue.isExpanded, !group.wrappedValue.files.isEmpty {
                    Divider()
                        .padding(.leading, AppSpacing.xl)

                    ForEach(Array(group.wrappedValue.files.indices), id: \.self) { fi in
                        fileRow(
                            file: group.files[fi],
                            toggle: {
                                viewModel.toggleFile(group.wrappedValue.files[fi].id)
                            }
                        )

                        if fi < group.wrappedValue.files.count - 1 {
                            Divider()
                                .padding(.leading, AppSpacing.xl)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Group Header

    private func groupHeader(_ group: Binding<DuplicateGroup>) -> some View {
        HStack(spacing: AppSpacing.sm) {
            // Expand / collapse chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textSecondary)
                .rotationEffect(.degrees(group.wrappedValue.isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.2), value: group.wrappedValue.isExpanded)
                .onTapGesture {
                    viewModel.toggleExpanded(group.wrappedValue.id)
                }
                .frame(width: 16)

            // Group-level checkbox (toggle all)
            Toggle(isOn: Binding(
                get: { group.wrappedValue.files.allSatisfy(\.isSelected) },
                set: { _ in viewModel.toggleGroup(group.wrappedValue.id) }
            )) { }
            .toggleStyle(.checkbox)
            .controlSize(.small)

            // Common file type icon
            Image(systemName: iconForGroup(group.wrappedValue))
                .foregroundColor(.textPrimary)
                .font(.system(size: 14))
                .frame(width: 18)

            // Name + count
            VStack(alignment: .leading, spacing: 1) {
                Text(commonName(for: group.wrappedValue))
                    .font(AppFont.body)
                    .fontWeight(.medium)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                Text("\(group.wrappedValue.files.count) files")
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            // Size each
            Text(FileSizeFormatter.abbreviated(from: group.wrappedValue.fileSize))
                .font(AppFont.monoDigit)
                .foregroundColor(.textSecondary)
                .frame(minWidth: 60, alignment: .trailing)

            // Total wasted
            Text(FileSizeFormatter.abbreviated(from: group.wrappedValue.totalWasted))
                .font(AppFont.monoDigit)
                .foregroundColor(.danger)
                .frame(minWidth: 60, alignment: .trailing)
        }
        .padding(AppSpacing.md)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.toggleExpanded(group.wrappedValue.id)
        }
    }

    // MARK: - File Row

    private func fileRow(file: Binding<DuplicatedFile>, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: AppSpacing.sm) {
            // Spacer for alignment under chevron
            Color.clear
                .frame(width: 16)

            // Checkbox
            Toggle(isOn: file.isSelected) { }
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .onTapGesture { toggle() }

            // File type icon
            Image(systemName: iconForFile(file.wrappedValue.url))
                .foregroundColor(.textSecondary)
                .font(.system(size: 13))
                .frame(width: 18)

            // Name + path
            VStack(alignment: .leading, spacing: 1) {
                Text(file.wrappedValue.fileName)
                    .font(AppFont.callout)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Text(abbreviatePath(file.wrappedValue.path))
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Modification date
            Text(file.wrappedValue.modificationDate, style: .date)
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
                .frame(minWidth: 70, alignment: .trailing)

            // Size
            Text(FileSizeFormatter.abbreviated(from: file.wrappedValue.size))
                .font(AppFont.monoDigit)
                .foregroundColor(.textSecondary)
                .frame(minWidth: 60, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.trailing, AppSpacing.md)
        .padding(.leading, AppSpacing.sm)
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: AppSpacing.md) {
            // Stats
            HStack(spacing: AppSpacing.sm) {
                statLabel("Groups", value: "\(viewModel.groups.count)")
                Divider()
                    .frame(height: 16)
                statLabel("Wasted", value: FileSizeFormatter.abbreviated(from: viewModel.totalWasted))
                Divider()
                    .frame(height: 16)
                statLabel("Selected", value: "\(viewModel.selectedCount)")
                statLabel("Size", value: FileSizeFormatter.abbreviated(from: viewModel.selectedSize))
            }

            Spacer()

            // Action buttons
            if !viewModel.groups.isEmpty {
                HStack(spacing: AppSpacing.sm) {
                    Button("Select All") {
                        viewModel.selectAllDuplicates()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Deselect") {
                        viewModel.deselectAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Clean Up (\(viewModel.selectedCount))") {
                        Task { try? await viewModel.cleanupSelected() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.danger)
                    .disabled(viewModel.selectedCount == 0)
                }
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

    private func commonName(for group: DuplicateGroup) -> String {
        guard let first = group.files.first?.fileName else { return "Unknown" }
        // Check if all files share the same name.
        let allSame = group.files.allSatisfy { $0.fileName == first }
        if allSame { return first }
        return "\(first) (\(group.files.count) variants)"
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func iconForGroup(_ group: DuplicateGroup) -> String {
        group.files.first.map { iconForFile($0.url) } ?? "doc"
    }

    private func iconForFile(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif", "svg":
            return "photo"
        case "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm":
            return "video"
        case "mp3", "wav", "aac", "flac", "m4a", "ogg", "wma":
            return "music.note"
        case "pdf":
            return "pdf"
        case "doc", "docx", "rtf", "pages":
            return "doc.text"
        case "xls", "xlsx", "csv", "numbers":
            return "tablecells"
        case "ppt", "pptx", "key":
            return "rectangle.3.group"
        case "zip", "tar", "gz", "bz2", "7z", "rar", "zst":
            return "archivebox"
        case "swift", "js", "ts", "py", "go", "rs", "cpp", "c", "h", "java", "kt":
            return "chevron.left.forwardslash.chevron.right"
        case "app", "dmg", "pkg":
            return "app"
        case "dmg":
            return "opticaldisc"
        default:
            return "doc"
        }
    }
}

// MARK: - Folder Picker (AppKit bridge)

/// A transparent `NSViewRepresentable` that presents an `NSOpenPanel` for folder
/// selection when `$isPresented` becomes `true`.
private struct FolderPickerView: NSViewRepresentable {
    @Binding var isPresented: Bool
    let onCompletion: ([URL]) -> Void

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard isPresented, let window = nsView.window else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.message = "Select folders to scan for duplicate files"
        panel.prompt = "Select"

        panel.beginSheetModal(for: window) { response in
            isPresented = false
            if response == .OK {
                onCompletion(panel.urls)
            }
        }
    }
}
