import SwiftUI
import AppKit
import DesignSystem
import CommonUtils
import AppCatalogCore

// MARK: - App Uninstall View

public struct AppUninstallView: View {
    @StateObject private var viewModel: AppUninstallViewModel
    @State private var showConfirmDialog = false
    @State private var uninstallResult: (succeeded: [String], failed: [String])?
    @State private var isUninstalling = false

    /// Injectable for the app root (graph engine + quota routing);
    /// previews fall back to a default-constructed view model.
    public init(viewModel: AppUninstallViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? AppUninstallViewModel())
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            contentArea
            summaryBar
        }
        .frame(minWidth: 680, minHeight: 420)
        .confirmationDialog(
            "确认卸载",
            isPresented: $showConfirmDialog,
            titleVisibility: .visible
        ) {
            Button("卸载 (\(viewModel.selectedEntries.count) 个应用)") {
                performUninstall()
            }
            .keyboardShortcut(.defaultAction)
            Button("取消", role: .cancel) {}
        } message: {
            let size = FileSizeFormatter.string(from: viewModel.selectedSize)
            let running = viewModel.selectedEntries.filter(\.isRunning).count
            let runningNote = running > 0
                ? "⚠️ 有 \(running) 个应用正在运行，建议先退出再卸载。"
                : ""
            Text("将 \(viewModel.selectedEntries.count) 个应用及其残留文件移入废纸篓，可回收 \(size) 空间。残留会先备份 30 天，可从备份还原。\(runningNote)")
        }
        .alert("卸载结果", isPresented: Binding(
            get: { uninstallResult != nil },
            set: { if !$0 { uninstallResult = nil } }
        )) {
            Button("好") { uninstallResult = nil }
        } message: {
            if let result = uninstallResult {
                let summary = result.succeeded.map { "\($0) (成功)" }.joined(separator: "\n")
                + (result.failed.isEmpty ? "" : "\n\n" + result.failed.map { "\($0) (失败)" }.joined(separator: "\n"))
                Text(summary)
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: AppSpacing.md) {
            Text("应用卸载")
                .font(AppFont.title2)
                .foregroundColor(.textPrimary)

            Spacer()

            searchAndFilterBar

            sortPicker

            if viewModel.isScanning {
                ProgressView()
                    .scaleEffect(0.8)
                    .controlSize(.small)
                Text("扫描中...")
                    .font(AppFont.callout)
                    .foregroundColor(.textSecondary)
            }

            Button {
                viewModel.startScan()
            } label: {
                Label("扫描", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)
            .disabled(viewModel.isScanning)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
    }

    private var searchAndFilterBar: some View {
        HStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                TextField("搜索应用或 Bundle ID", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                    .font(AppFont.callout)
            }

            Picker("来源", selection: $viewModel.sourceFilter) {
                Text("全部来源").tag(AppSource?.none)
                Text("用户安装").tag(AppSource?.some(.userInstalled))
                Text("App Store").tag(AppSource?.some(.mas))
                Text("Homebrew").tag(AppSource?.some(.homebrew))
                Text("Setapp").tag(AppSource?.some(.setapp))
            }
            .pickerStyle(.menu)
            .frame(width: 130)

            sortPicker
        }
    }

    private var sortPicker: some View {
        HStack(spacing: AppSpacing.xs) {
            Text("排序:")
                .font(AppFont.callout)
                .foregroundColor(.textSecondary)

            Picker("排序字段", selection: $viewModel.sortBy) {
                ForEach(AppUninstallViewModel.SortField.allCases, id: \.self) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 100)
            .onChange(of: viewModel.sortBy) { _ in
                viewModel.toggleSort(viewModel.sortBy)
            }

            Button {
                viewModel.sortAscending.toggle()
                viewModel.toggleSort(viewModel.sortBy)
            } label: {
                Image(systemName: viewModel.sortAscending ? "arrow.up" : "arrow.down")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help(viewModel.sortAscending ? "升序" : "降序")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.entries.isEmpty && !viewModel.isScanning {
            emptyState
        } else {
            appList
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "app.dashed",
            title: "尚未扫描",
            subtitle: "点击「扫描」以检测已安装的应用",
            action: (title: "开始扫描", handler: { viewModel.startScan() })
        )
    }

    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.xs) {
                ForEach(viewModel.visibleEntries) { entry in
                    AppRow(
                        entry: entry,
                        onToggle: { viewModel.toggleSelection(entry.id) }
                    )
                    .padding(.horizontal, AppSpacing.lg)
                }
            }
            .padding(.vertical, AppSpacing.sm)
        }
        .background(Color.bgPrimary)
    }

    // MARK: - Summary

    private var summaryBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: AppSpacing.lg) {
                Text("共 \(viewModel.entries.count) 个应用")
                    .font(AppFont.callout)
                    .foregroundColor(.textSecondary)

                if viewModel.appsWithLeftovers > 0 {
                    Text("\(viewModel.appsWithLeftovers) 个有残留文件")
                        .font(AppFont.callout)
                        .foregroundColor(.warning)
                }

                Spacer()

                if !viewModel.selectedEntries.isEmpty {
                    Text("已选 \(viewModel.selectedEntries.count) 个")
                        .font(AppFont.callout)
                        .foregroundColor(.textPrimary)

                    Text("可回收 \(FileSizeFormatter.string(from: viewModel.selectedSize))")
                        .font(AppFont.callout)
                        .foregroundColor(.brandPrimary)

                    Button {
                        showConfirmDialog = true
                    } label: {
                        Text("卸载 (\(viewModel.selectedEntries.count))")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.danger)
                    .disabled(isUninstalling)
                } else {
                    Text("未选择任何应用")
                        .font(AppFont.callout)
                        .foregroundColor(.textSecondary)

                    Button("全选") {
                        viewModel.selectAll()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
    }

    // MARK: - Actions

    private func performUninstall() {
        isUninstalling = true
        Task {
            let backupStore = UninstallBackupStore()
            for entry in viewModel.selectedEntries where !entry.residues.isEmpty {
                try? await backupStore.backupBeforeUninstall(entry: entry)
            }
            await backupStore.pruneExpired(days: 30)
            // 卸载联动 (v2.4)：残留中含 LaunchAgents 的 App 一并停用其启动项。
            let toggler = StartupItemToggler(persistence: .shared)
            for entry in viewModel.selectedEntries {
                for url in entry.residues.map(\.url) where url.path.contains("LaunchAgents") {
                    let plistEntry = LoginItemEntry(
                        label: entry.bundleID, plistURL: url,
                        programPath: nil, runAtLoad: true, keepAlive: false,
                        scope: .user
                    )
                    _ = await toggler.disable(plistEntry)
                }
            }
            let result = await viewModel.uninstallSelected()
            uninstallResult = result
            isUninstalling = false
        }
    }
}

// MARK: - App Row

private struct AppRow: View {
    @State private var isExpanded = false
    let entry: UninstallAppEntry
    let onToggle: () -> Void

    private func sourceBadge(_ source: AppSource) -> String {
        switch source {
        case .mas: return "App Store"
        case .homebrew: return "Homebrew"
        case .setapp: return "Setapp"
        case .userInstalled: return "用户安装"
        default: return ""
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.md) {
                // Checkbox
                Toggle("", isOn: Binding(
                    get: { entry.isSelected },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()

                // App Icon
                iconView
                    .frame(width: 36, height: 36)

                // App Info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AppSpacing.xs) {
                        if entry.isOrphan {
                            Text("应用已删除")
                                .font(AppFont.caption)
                                .foregroundColor(.warning)
                                .padding(.horizontal, 5)
                                .background(Color.warning.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        if entry.isRunning {
                            Circle()
                                .fill(Color.stateWarning)
                                .frame(width: 7, height: 7)
                                .help("应用正在运行，建议先退出")
                        }
                        Text(entry.appName)
                            .font(AppFont.body)
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                        Text(sourceBadge(entry.source))
                            .font(AppFont.caption)
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 5)
                            .background(Color.bgSecondary)
                            .clipShape(Capsule())
                    }

                    HStack(spacing: AppSpacing.sm) {
                        Text(entry.bundleID)
                            .font(AppFont.caption)
                            .foregroundColor(.textSecondary)
                            .lineLimit(1)
                        if let lastUsed = entry.lastUsedDate {
                            Text("最近使用 \(lastUsed, style: .relative)")
                                .font(AppFont.caption)
                                .foregroundColor(.textSecondary)
                        } else {
                            Text("最近使用：未知")
                                .font(AppFont.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }
                }

                Spacer()

                // Size breakdown
                HStack(spacing: AppSpacing.sm) {
                    // App size
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(FileSizeFormatter.abbreviated(from: entry.appSize))
                            .font(AppFont.monoDigit)
                            .foregroundColor(.textPrimary)
                        Text("应用本体")
                            .font(AppFont.caption)
                            .foregroundColor(.textSecondary)
                    }

                    if entry.leftoverSize > 0 {
                        // Leftover size
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(FileSizeFormatter.abbreviated(from: entry.leftoverSize))
                                .font(AppFont.monoDigit)
                                .foregroundColor(.warning)
                            Text("残留")
                                .font(AppFont.caption)
                                .foregroundColor(.textSecondary)
                        }

                        // Total size bar
                        totalSizeBar
                            .frame(width: 60)
                    }
                }

                // Detail disclosure
                if entry.leftoverSize > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, AppSpacing.sm)
            .padding(.horizontal, AppSpacing.sm)
            .background(Color.bgSecondary.opacity(0.3))
            .cornerRadius(AppSpacing.sm)
            .contextMenu {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([entry.appURL])
                } label: {
                    Label("在Finder中显示", systemImage: "folder")
                }
            }

            // Expanded leftover list
            if isExpanded && !entry.leftoverURLs.isEmpty {
                leftoverList
            }
        }
    }

    @ViewBuilder
    private var iconView: some View {
        let image = NSWorkspace.shared.icon(forFile: entry.appURL.path)
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    private var totalSizeBar: some View {
        let total = max(entry.totalSize, 1)
        let leftoverRatio = CGFloat(entry.leftoverSize) / CGFloat(total)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.separatorColor.opacity(0.3))
                    .frame(height: 6)
                Capsule()
                    .fill(Color.warning)
                    .frame(width: geo.size.width * leftoverRatio, height: 6)
            }
        }
        .frame(height: 6)
    }

    private var leftoverList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("残留文件 (\(entry.leftoverURLs.count))")
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
                .padding(.leading, AppSpacing.sm)

            ForEach(entry.leftoverURLs, id: \.path) { url in
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "doc")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                    Text(abbreviatedPath(url.path))
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    let size = directorySizeAtURL(url)
                    Text(FileSizeFormatter.abbreviated(from: size))
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, AppSpacing.xs)
        .padding(.leading, 52) // align with app name text
        .background(Color.bgTertiary.opacity(0.15))
        .cornerRadius(AppSpacing.sm)
    }

    // MARK: - Helpers

    /// Shorten the home directory prefix for display.
    private func abbreviatedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func directorySizeAtURL(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else { continue }
            total += Int64(size)
        }
        return total
    }
}
