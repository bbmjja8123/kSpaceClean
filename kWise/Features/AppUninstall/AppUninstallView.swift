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

    /// 孤儿条目「清理残留」待确认项（独立于卸载确认弹窗 —— 孤儿没有
    /// App 本体，文案与提交范围都必须与「卸载」分开）。
    @State private var residueCleanupEntry: UninstallAppEntry?

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
            confirmDialogTitle,
            isPresented: $showConfirmDialog,
            titleVisibility: .visible
        ) {
            Button(confirmButtonTitle) {
                performUninstall()
            }
            .keyboardShortcut(.defaultAction)
            Button("取消", role: .cancel) {}
        } message: {
            Text(confirmMessage)
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

    /// 孤儿清理规模：面板有显式勾选 → 只算勾选的残留；否则整条目残留。
    private var residueCleanupSize: Int64 {
        guard let entry = residueCleanupEntry else { return 0 }
        if let explicit = viewModel.selectedResiduePaths[entry.id], !explicit.isEmpty {
            return entry.residues
                .filter { explicit.contains($0.url.path) }
                .reduce(0) { $0 + $1.sizeBytes }
        }
        return entry.leftoverSize
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
            // 双栏（v2.6 Task 4）：左 260pt 列表 + 右详情面板。
            HStack(spacing: 0) {
                appList
                    .frame(width: 260)
                Divider()
                AppUninstallDetailPanel(
                    viewModel: viewModel,
                    onUninstall: { entry in
                        // 面板「卸载」= 只选中该条目后走卸载确认弹窗。
                        viewModel.deselectAll()
                        viewModel.toggleSelection(entry.id)
                        showConfirmDialog = true
                    },
                    onCleanupResidues: { entry in
                        // 孤儿「清理残留」= 独立的残留确认弹窗（文案
                        // 「清理残留 (N MB)」），提交时不含 App 本体。
                        residueCleanupEntry = entry
                    }
                )
            }
            // 孤儿条目「清理残留」确认弹窗（与卸载弹窗分别挂在不同视图，
            // 避免 confirmationDialog 同视图竞争 present）。
            .confirmationDialog(
                "确认清理残留",
                isPresented: Binding(
                    get: { residueCleanupEntry != nil },
                    set: { if !$0 { residueCleanupEntry = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("清理残留 (\(FileSizeFormatter.string(from: residueCleanupSize)))") {
                    performResidueCleanup()
                }
                .keyboardShortcut(.defaultAction)
                Button("取消", role: .cancel) {}
            } message: {
                let size = FileSizeFormatter.string(from: residueCleanupSize)
                Text("将 \(residueCleanupEntry?.appName ?? "") 的残留文件移入废纸篓，可回收 \(size) 空间。残留会先备份 30 天，可从备份还原。")
            }
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
                        isSelectedRow: viewModel.selectedEntryID == entry.id,
                        onToggle: { viewModel.toggleSelection(entry.id) },
                        onReset: {
                            Task { try? await viewModel.resetApp(entry) }
                        },
                        onSelect: { viewModel.selectedEntryID = entry.id }
                    )
                    .padding(.horizontal, AppSpacing.sm)
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

                    // 与确认弹窗同口径：按实际提交范围（明细/孤儿语义）计。
                    Text("可回收 \(FileSizeFormatter.string(from: viewModel.selectedCommitSize))")
                        .font(AppFont.callout)
                        .foregroundColor(.brandPrimary)

                    Button {
                        showConfirmDialog = true
                    } label: {
                        // 全孤儿选择 → 语义是清理残留，不是卸载（审查 M-2）。
                        Text(allSelectedAreOrphans
                             ? "清理残留 (\(viewModel.selectedEntries.count))"
                             : "卸载 (\(viewModel.selectedEntries.count))")
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

    // MARK: - Confirm Dialog Copy（与提交范围同口径）

    /// 待卸载条目是否全部为孤儿（列表勾选孤儿 → 弹窗语义是「清理残留」
    /// 而非「卸载」—— 孤儿没有 App 本体可卸载，审查 M-2）。
    private var allSelectedAreOrphans: Bool {
        !viewModel.selectedEntries.isEmpty
            && viewModel.selectedEntries.allSatisfy(\.isOrphan)
    }

    /// 明细模式（审查 I-1）：面板条目出现过显式残留勾选（全局 flag 仅作
    /// 文案门槛）且该条目仍在待卸载列表 → 弹窗按提交范围显示。提交范围
    /// 本身仍由 VM 按条目解析（`selectedCommitSize` / `uninstallSelected`）。
    private var isDetailModeConfirm: Bool {
        viewModel.hasExplicitResidueSelection
            && viewModel.selectedEntries.contains { $0.id == viewModel.selectedEntryID }
    }

    private var confirmDialogTitle: String {
        if allSelectedAreOrphans { return "确认清理残留" }
        if isDetailModeConfirm {
            return "卸载 (\(viewModel.selectedEntries.count) 个应用，部分残留)"
        }
        return "确认卸载"
    }

    private var confirmButtonTitle: String {
        if allSelectedAreOrphans {
            // 审查 M-e：孤儿语境的「N 项」指残留文件项数（提交范围），
            // 不是所选条目数 —— 条目数会严重低估实际清理规模。
            return "清理残留 (\(viewModel.selectedCommitResidueCount) 项残留)"
        }
        let count = viewModel.selectedEntries.count
        if isDetailModeConfirm { return "卸载 (\(count) 个应用，部分残留)" }
        return "卸载 (\(count) 个应用)"
    }

    private var confirmMessage: String {
        // 可回收空间 = 实际提交范围（本体 + 勾选/全部残留；孤儿仅残留）。
        let size = FileSizeFormatter.string(from: viewModel.selectedCommitSize)
        let backupNote = "残留会先备份 30 天，可从备份还原。"

        if allSelectedAreOrphans {
            // 审查 M-e：N = 提交范围内的残留项数（与按钮标题同口径）。
            return "将 \(viewModel.selectedCommitResidueCount) 项残留文件移入废纸篓，可回收 \(size) 空间。\(backupNote)"
        }

        if isDetailModeConfirm {
            return "将 \(viewModel.selectedEntries.count) 个应用移入废纸篓，仅清理勾选的 \(viewModel.selectedPickedResidueCount) 项残留，可回收 \(size) 空间。\(backupNote)"
        }

        let running = viewModel.selectedEntries.filter(\.isRunning).count
        let runningNote = running > 0
            ? "⚠️ 有 \(running) 个应用正在运行，建议先退出再卸载。"
            : ""
        let sharedNote = viewModel.selectedEntries.compactMap {
            viewModel.sharedComponentWarning(for: $0)
        }.joined(separator: "\n")
        let sharedBlock = sharedNote.isEmpty ? "" : "\n\(sharedNote)"
        return "将 \(viewModel.selectedEntries.count) 个应用及其残留文件移入废纸篓，可回收 \(size) 空间。\(backupNote)\(runningNote)\(sharedBlock)"
    }

    // MARK: - Actions

    /// 孤儿条目「清理残留」确认后：只选中该条目走既有卸载管线。
    /// 提交范围由 VM 按 `isOrphan` 收敛为仅残留（appURL 不进 CleanupTarget），
    /// 备份 / 启动项停用 / 历史 / 配额与正常卸载同一管线。
    private func performResidueCleanup() {
        guard let entry = residueCleanupEntry else { return }
        residueCleanupEntry = nil
        viewModel.deselectAll()
        viewModel.toggleSelection(entry.id)
        performUninstall()
    }

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
    /// 双栏选中高亮（右侧详情面板展示该条目时为 true）。
    var isSelectedRow: Bool = false
    let onToggle: () -> Void
    var onReset: (() -> Void)? = nil
    /// 点击行 → 打开右侧详情面板（行内展开保留为只读快览）。
    var onSelect: (() -> Void)? = nil

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
            .background(
                isSelectedRow
                    ? Color.brandPrimary.opacity(0.15)
                    : Color.bgSecondary.opacity(0.3)
            )
            .cornerRadius(AppSpacing.sm)
            .contentShape(Rectangle())
            .onTapGesture { onSelect?() }
            .contextMenu {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([entry.appURL])
                } label: {
                    Label("在Finder中显示", systemImage: "folder")
                }
                if let onReset {
                    Button {
                        onReset()
                    } label: {
                        Label("App Reset（保留应用，清偏好与缓存）", systemImage: "arrow.counterclockwise")
                    }
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
