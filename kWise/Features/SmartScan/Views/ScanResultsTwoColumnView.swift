import SwiftUI
import DesignSystem
import CommonUtils

// MARK: - RT-C Two-Column Result View

/// RT-C layout (CMM X style):
///   Left  = app list (checkbox / risk icon / name / size)
///   Right = selected app files (checkbox / name / muted path / size)
///   Right top = AppDetailHeader + 1-line safety banner
///   No per-file risk chip, no indented path tree, no per-app risk tabs.
///   Risk filtering is done globally via `RiskFilterBar` at top.
@MainActor
struct ScanResultsTwoColumnView: View {
    @ObservedObject var viewModel: ScanViewModel
    @State private var selectedAppID: Int? = nil
    @State private var searchText: String = ""
    @State private var riskFilter: RiskFilter = .all

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider().background(Color.separatorColor.opacity(0.5))
            twoColumnBody
            Divider().background(Color.separatorColor.opacity(0.5))
            ScanSummaryBar(
                totalItems: filteredApps.reduce(0) { $0 + $1.items.count },
                totalSize: filteredApps.reduce(0) { $0 + $1.totalSize },
                selectedItems: viewModel.selectedCount,
                selectedSize: viewModel.selectedSize,
                onCleanup: { viewModel.startCleanup() }
            )
        }
        .modifier(ScanResultsKeyboardShortcuts(riskFilter: $riskFilter,
                                                 onCleanup: { viewModel.startCleanup() }))
        .onAppear {
            if selectedAppID == nil {
                selectedAppID = filteredApps.first?.id
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(spacing: 6) {
            RiskFilterBar(riskFilter: $riskFilter, stats: viewModel.riskGroupedStats)
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textSecondary)
                TextField("搜索应用 / 文件名 / 路径...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(AppFont.callout)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.textSecondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 6)
            .background(Color.bgTertiary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, AppSpacing.md)
            .padding(.bottom, 6)
        }
        .padding(.top, 6)
    }

    // MARK: - Two-column body

    private var twoColumnBody: some View {
        HSplitView {
            appListColumn
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            detailColumn
                .frame(minWidth: 360)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Left column: app list

    private var appListColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text("应用")
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
                Spacer()
                Text("\(filteredApps.count) 项 · \(FileSizeFormatter.abbreviated(from: filteredApps.reduce(0) { $0 + $1.totalSize }))")
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 6)
            .background(Color.bgTertiary.opacity(0.2))

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredApps) { app in
                        AppRowView(
                            app: app,
                            isSelected: app.id == selectedAppID,
                            onTap: { selectedAppID = app.id },
                            onToggle: { viewModel.toggleActionGroup(app.id) }
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
        .background(Color.bgPrimary.opacity(0.5))
    }

    // MARK: - Right column: file detail

    private var detailColumn: some View {
        VStack(spacing: 0) {
            if let app = selectedApp {
                AppDetailHeader(app: app,
                                onCleanOnlyThis: { cleanOnlyThisApp(app) })
                safetyBanner(app: app)
                Divider().background(Color.separatorColor.opacity(0.5))
                FileListView(app: app,
                             searchText: searchText,
                             riskFilter: riskFilter,
                             viewModel: viewModel)
            } else {
                emptyDetailState
            }
        }
    }

    private func safetyBanner(app: ActionGroup) -> some View {
        let count = app.items.count
        let size = app.totalSize
        let text: String
        switch app.riskLevel {
        case .dangerous:
            text = "⚠️ 此应用文件风险较高,建议确认后再清理"
        case .caution:
            text = "⚠️ 部分文件需谨慎,建议确认后再清理"
        case .optional:
            text = "这些文件可选清理,如不再使用可安全移除"
        case .recommended:
            text = "缓存文件默认勾选,\(count) 个文件共 \(FileSizeFormatter.abbreviated(from: size)) 可安全释放"
        }
        return HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
            Text(text)
                .font(.system(size: 12))
        }
        .foregroundColor(safetyColor(for: app.riskLevel))
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(safetyColor(for: app.riskLevel).opacity(0.08))
    }

    private func safetyColor(for level: RiskLevel) -> Color {
        switch level {
        case .dangerous: return .danger
        case .caution: return .orange
        case .recommended: return .success
        case .optional: return .textSecondary
        }
    }

    private var emptyDetailState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.textSecondary.opacity(0.5))
            Text("选择一个应用查看详情")
                .font(AppFont.body)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data shaping

    private var filteredApps: [ActionGroup] {
        var apps: [ActionGroup] = []
        for group in viewModel.resultGroups {
            for ag in group.actionGroups {
                if !riskFilter.matches(ag.riskLevel) { continue }
                if !searchText.isEmpty {
                    let inApp = (ag.appName ?? ag.title)
                        .localizedCaseInsensitiveContains(searchText)
                    let anyItem = ag.items.contains {
                        $0.fileName.localizedCaseInsensitiveContains(searchText) ||
                        $0.path.localizedCaseInsensitiveContains(searchText)
                    }
                    if !inApp && !anyItem { continue }
                }
                apps.append(ag)
            }
        }
        return apps.sorted { $0.totalSize > $1.totalSize }
    }

    private var selectedApp: ActionGroup? {
        guard let id = selectedAppID else { return nil }
        return filteredApps.first { $0.id == id }
    }

    // MARK: - Actions

    private func cleanOnlyThisApp(_ app: ActionGroup) {
        for group in viewModel.resultGroups {
            for ag in group.actionGroups {
                if ag.isAllSelected {
                    viewModel.toggleActionGroup(ag.id)
                }
            }
        }
        if !app.isAllSelected {
            viewModel.toggleActionGroup(app.id)
        }
        viewModel.startCleanup()
    }
}

// MARK: - App Row (left column item)

@MainActor
private struct AppRowView: View {
    let app: ActionGroup
    let isSelected: Bool
    let onTap: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: app.isAllSelected ? "checkmark.square.fill" : "square")
                .font(.system(size: 14))
                .foregroundColor(app.isAllSelected ? .brandPrimary : .textSecondary)
                .onTapGesture { onToggle() }

            Image(systemName: riskIcon)
                .font(.system(size: 12))
                .foregroundColor(riskColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.appName ?? app.title)
                    .font(AppFont.body)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                if let appName = app.appName, appName != app.title {
                    Text(app.title)
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Text(FileSizeFormatter.abbreviated(from: app.totalSize))
                .font(AppFont.monoDigit)
                .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 6)
        .background(
            isSelected ? Color.brandPrimary.opacity(0.12) : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var riskIcon: String {
        switch app.riskLevel {
        case .dangerous: return "exclamationmark.triangle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .optional: return "circle"
        case .recommended: return "checkmark.circle.fill"
        }
    }

    private var riskColor: Color {
        switch app.riskLevel {
        case .dangerous: return .danger
        case .caution: return .orange
        case .optional: return .textSecondary
        case .recommended: return .success
        }
    }
}

// MARK: - App Detail Header (right column top)

@MainActor
private struct AppDetailHeader: View {
    let app: ActionGroup
    let onCleanOnlyThis: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(app.appName ?? app.title)
                        .font(AppFont.title3)
                        .foregroundColor(.textPrimary)
                    riskBadge
                }
                HStack(spacing: 12) {
                    Label("\(app.items.count) 个文件", systemImage: "doc")
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                    Label(FileSizeFormatter.abbreviated(from: app.totalSize),
                          systemImage: "arrow.down.circle")
                        .font(AppFont.caption)
                        .foregroundColor(.brandPrimary)
                    if app.selectedSize > 0 {
                        Label("已选 \(FileSizeFormatter.abbreviated(from: app.selectedSize))",
                              systemImage: "checkmark.circle.fill")
                            .font(AppFont.caption)
                            .foregroundColor(.brandPrimary)
                    }
                }
            }
            Spacer()
            Button {
                onCleanOnlyThis()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("仅清理此应用")
                }
            }
            .buttonStyle(.bordered)
            .tint(.danger)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .background(Color.bgTertiary.opacity(0.3))
    }

    @ViewBuilder
    private var riskBadge: some View {
        switch app.riskLevel {
        case .dangerous:
            badge(text: "危险", color: .danger)
        case .caution:
            badge(text: "注意", color: .orange)
        case .optional:
            badge(text: "可选", color: .textSecondary)
        case .recommended:
            badge(text: "推荐", color: .success)
        }
    }

    private func badge(text: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8))
            Text(text)
        }
        .font(.system(size: 9, weight: .medium))
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(color.opacity(0.2))
        .foregroundColor(color)
        .clipShape(Capsule())
    }
}

// MARK: - File List (right column body)

private struct FileListView: View {
    let app: ActionGroup
    let searchText: String
    let riskFilter: RiskFilter
    @ObservedObject var viewModel: ScanViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredItems) { node in
                    TwoColumnFileRow(node: node, viewModel: viewModel)
                    Divider()
                        .background(Color.separatorColor.opacity(0.2))
                        .padding(.leading, AppSpacing.lg)
                }
                if filteredItems.isEmpty {
                    Text("没有匹配的文件")
                        .font(AppFont.body)
                        .foregroundColor(.textSecondary)
                        .padding(AppSpacing.xl)
                }
            }
        }
    }

    private var filteredItems: [ScanResultNode] {
        var items = app.items
        if riskFilter != .all {
            items = items.filter { riskFilter.matches($0.riskLevel) }
        }
        if !searchText.isEmpty {
            items = items.filter {
                $0.fileName.localizedCaseInsensitiveContains(searchText) ||
                $0.path.localizedCaseInsensitiveContains(searchText)
            }
        }
        return items
    }
}

// MARK: - File Row (CMM X style: checkbox + icon + name + 1-line muted path + size)

@MainActor
private struct TwoColumnFileRow: View {
    let node: ScanResultNode
    @ObservedObject var viewModel: ScanViewModel

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            // Checkbox
            Image(systemName: node.isSelected ? "checkmark.square.fill" : "square")
                .font(.system(size: 14))
                .foregroundColor(node.isSelected ? .brandPrimary : .textSecondary)
                .onTapGesture { viewModel.toggleItem(node.id) }

            // File icon
            if let cat = FileCategory(rawValue: node.fileEntry.category ?? "") {
                Image(systemName: cat.icon)
                    .font(.system(size: 11))
                    .foregroundColor(cat.color)
            }

            // File name + single-line muted path
            VStack(alignment: .leading, spacing: 1) {
                Text(node.fileName)
                    .font(AppFont.body)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Text(truncatedPath(node.path))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            // Size
            Text(FileSizeFormatter.abbreviated(from: node.size))
                .font(AppFont.monoDigit)
                .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    /// Single-line truncated path: ~/Library/Caches/WeChat/...
    /// Keeps parent dir structure visible but compact.
    private func truncatedPath(_ path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count > 4 else { return path }
        let last4 = parts.suffix(3)
        return "~/…/" + last4.joined(separator: "/")
    }
}
