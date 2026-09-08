import SwiftUI
import DesignSystem
import CommonUtils
import DetectionCore

/// Main view for duplicate file detection and cleanup (v2.3 Phase 2).
///
/// Renders `ToolboxGroup`s from the DetectionCore pipeline: category/evidence
/// badges, similarity %, honest APFS-clone banners, keep-strategy picker,
/// thumbnails, space-key QuickLook, and per-file keep reasons.
struct DuplicateView: View {
    @ObservedObject var viewModel: DuplicateViewModel
    @State private var showFolderPicker = false
    @State private var previewURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            configBar
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)

            if let warning = viewModel.lastWarning {
                warningBar(warning)
            }

            if viewModel.groups.isEmpty, !viewModel.isScanning {
                emptyState
            } else {
                contentArea
            }
        }
        .kwQuickLookPreview($previewURL)
    }

    // MARK: - Config Bar

    private var configBar: some View {
        HStack(spacing: AppSpacing.md) {
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

            // Keep strategy — 5 engine strategies with localized titles.
            Picker("保留策略", selection: $viewModel.strategy) {
                ForEach(SelectionStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.title).tag(strategy)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 150)
            .disabled(viewModel.isScanning)
            .help("选择每组中保留哪一份副本，其余自动勾选")

            Spacer()

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

    // MARK: - Warning Bar (honest scope/engine notices)

    private func warningBar(_ message: String) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "info.circle")
                .foregroundColor(.textSecondary)
            Text(message)
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xs)
        .background(Color.bgSecondary.opacity(0.5))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "doc.on.doc",
            title: "Find Duplicate Files",
            subtitle: "字节级相同、APFS 克隆与视觉相似文件会被分组展示。空间不足时先授权主目录。"
        )
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(spacing: 0) {
            if viewModel.isScanning {
                scanningProgress
            }

            ScrollView {
                LazyVStack(spacing: AppSpacing.sm) {
                    ForEach($viewModel.groups) { $group in
                        groupSection($group)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
            }

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
                Text("Scanning... \(viewModel.filesScanned) files")
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

    private func groupSection(_ group: Binding<ToolboxGroup>) -> some View {
        GlassPanel {
            VStack(spacing: 0) {
                groupHeader(group)

                if group.wrappedValue.isExpanded, !group.wrappedValue.files.isEmpty {
                    if group.wrappedValue.evidenceSummary.contains("克隆") {
                        cloneBanner
                        Divider().padding(.leading, AppSpacing.xl)
                    }
                    Divider()
                        .padding(.leading, AppSpacing.xl)

                    ForEach(Array(group.wrappedValue.files.indices), id: \.self) { fi in
                        fileRow(
                            file: group.files[fi],
                            preview: { previewURL = group.wrappedValue.files[fi].url }
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

    /// Honest notice for APFS clone sets (C-5): trashing clones reclaims
    /// almost nothing because they share physical extents.
    private var cloneBanner: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "externaldrive.badge.timemachine")
                .foregroundColor(.textSecondary)
            Text("这些副本是 APFS 克隆，删除几乎不会释放实际空间")
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .background(Color.bgSecondary.opacity(0.4))
    }

    // MARK: - Group Header

    private func groupHeader(_ group: Binding<ToolboxGroup>) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textSecondary)
                .rotationEffect(.degrees(group.wrappedValue.isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.2), value: group.wrappedValue.isExpanded)
                .onTapGesture {
                    viewModel.toggleExpanded(group.wrappedValue.id)
                }
                .frame(width: 16)

            Toggle(isOn: Binding(
                get: { group.wrappedValue.files.allSatisfy(\.isSelected) },
                set: { _ in viewModel.toggleGroup(group.wrappedValue.id) }
            )) { }
            .toggleStyle(.checkbox)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: AppSpacing.sm) {
                    Text(commonName(for: group.wrappedValue))
                        .font(AppFont.body)
                        .fontWeight(.medium)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    // Category/evidence badge — 字节级相同 / 视觉相似 x% / ...
                    Text(group.wrappedValue.evidenceSummary)
                        .font(AppFont.caption)
                        .foregroundColor(.brandPrimary)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 1)
                        .background(Color.brandPrimary.opacity(0.1))
                        .clipShape(Capsule())
                    if let similarity = group.wrappedValue.similarity {
                        Text(String(format: "%.0f%%", similarity * 100))
                            .font(AppFont.caption)
                            .foregroundColor(.textSecondary)
                    }
                }
                Text("\(group.wrappedValue.files.count) files")
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            if let size = group.wrappedValue.files.first?.size {
                Text(FileSizeFormatter.abbreviated(from: size))
                    .font(AppFont.monoDigit)
                    .foregroundColor(.textSecondary)
                    .frame(minWidth: 60, alignment: .trailing)
            }

            Text(FileSizeFormatter.abbreviated(from: group.wrappedValue.honestlyReclaimable))
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

    private func fileRow(file: Binding<ToolboxFile>, preview: @escaping () -> Void) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Color.clear
                .frame(width: 16)

            Toggle(isOn: file.isSelected) { }
                .toggleStyle(.checkbox)
                .controlSize(.small)

            KWThumbnailView(url: file.wrappedValue.url, size: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.wrappedValue.url.lastPathComponent)
                    .font(AppFont.callout)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Text(Self.abbreviatePath(file.wrappedValue.url.path))
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file.wrappedValue.url.path)  // C-1: raw path tooltip-only
                if let reason = file.wrappedValue.reason {
                    Text(reason)
                        .font(AppFont.caption)
                        .foregroundColor(.success)
                }
            }

            Spacer()

            Button {
                preview()
            } label: {
                Image(systemName: "eye")
                    .foregroundColor(.brandPrimary)
            }
            .buttonStyle(.borderless)
            .help("QuickLook 预览（或按空格键）")

            Text(file.wrappedValue.modificationDate, style: .date)
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
                .frame(minWidth: 70, alignment: .trailing)

            Text(FileSizeFormatter.abbreviated(from: file.wrappedValue.size))
                .font(AppFont.monoDigit)
                .foregroundColor(.textSecondary)
                .frame(minWidth: 60, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.trailing, AppSpacing.md)
        .padding(.leading, AppSpacing.sm)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { preview() }
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: AppSpacing.md) {
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

            if !viewModel.groups.isEmpty {
                HStack(spacing: AppSpacing.sm) {
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

    private func commonName(for group: ToolboxGroup) -> String {
        let name = group.files.first?.url.lastPathComponent ?? "Unknown"
        let allSame = group.files.allSatisfy { $0.url.lastPathComponent == name }
        if allSame { return name }
        return "\(name) (\(group.files.count) variants)"
    }

    static func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Folder Picker (AppKit bridge)

/// A transparent `NSViewRepresentable` that presents an `NSOpenPanel` for folder
/// selection when `$isPresented` becomes `true`.
struct FolderPickerView: NSViewRepresentable {
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
