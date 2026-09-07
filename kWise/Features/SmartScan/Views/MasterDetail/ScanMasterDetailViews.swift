// kWise/Features/SmartScan/Views/MasterDetail/ScanMasterDetailViews.swift
//
// 分类 → 应用 → 文件 三级主从视图 (UX 重构 Phase 2).
//
// Replaces the old `RecursiveTreeNode` tree that materialized an entire
// expanded subtree in one main-thread layout pass (the multi-second
// 应用缓存 freeze). Every list here renders a *capped slice* through
// `ScanResultsViewModel`'s row suppliers and expands lazily.
import SwiftUI
import AppKit
import DesignSystem

// MARK: - Root

struct ScanResultsMasterDetailView: View {
    @ObservedObject var viewModel: ScanResultsViewModel
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            CategoryColumnView(viewModel: viewModel)
                .frame(width: 280)
            Divider()
            DetailColumnView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.bgPrimary)
    }
}

// MARK: - Level 1: Category column

private struct CategoryColumnView: View {
    @ObservedObject var viewModel: ScanResultsViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.sm) {
                ForEach(viewModel.categories) { category in
                    CategoryCardView(
                        viewModel: viewModel,
                        category: category,
                        isFocused: viewModel.focusedCategory?.id == category.id
                    )
                }
            }
            .padding(AppSpacing.md)
        }
    }
}

private struct CategoryCardView: View {
    @ObservedObject var viewModel: ScanResultsViewModel
    let category: ScanCategory
    let isFocused: Bool
    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(KFAnimation.easeInOut) {
                viewModel.focus(category)
            }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: Self.icon(for: category.categoryID))
                    .font(.system(size: 18))
                    .foregroundStyle(Color.brandPrimary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(AppFont.body)
                        .foregroundStyle(Color.textPrimary)
                    Text(Self.formatBytes(category.totalSize))
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                if category.state != .unchecked {
                    Text("\(category.selectedSize > 0 ? Self.formatBytes(category.selectedSize) : "已选")")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.brandPrimary)
                }
                Image(systemName: "chevron.right")
                    .font(AppFont.caption)
                    .foregroundStyle(isFocused ? Color.brandPrimary : Color.textSecondary)
            }
            .padding(AppSpacing.md)
            .background(focusedBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
            .modifier(HoverShadowModifier(active: isHovering && !isFocused))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(KFAnimation.easeInOut) { isHovering = hovering }
        }
    }

    private var focusedBackground: Color {
        isFocused ? Color.brandPrimary.opacity(0.15) : Color.bgSecondary
    }

    /// categoryID → SF Symbol, mirroring the toolbox card set.
    static func icon(for categoryID: String) -> String {
        switch categoryID {
        case "system.cache", "system.junk": return "internaldrive"
        case "app.cache": return "shippingbox"
        case "web.junk": return "globe"
        case "mail.attachment": return "envelope"
        case "dev.junk": return "hammer"
        case "system.log": return "doc.text.magnifyingglass"
        default: return "folder"
        }
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}

// MARK: - Level 2: Detail column

private struct DetailColumnView: View {
    @ObservedObject var viewModel: ScanResultsViewModel

    var body: some View {
        if let category = viewModel.focusedCategory {
            AppRowsView(viewModel: viewModel, category: category)
        } else {
            EmptyStateView(
                icon: "square.grid.2x2",
                title: "选择一个分类",
                subtitle: "左侧选择分类查看可清理项。"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct AppRowsView: View {
    @ObservedObject var viewModel: ScanResultsViewModel
    let category: ScanCategory

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: AppSpacing.sm) {
                    let rows = viewModel.visibleSubcategories(in: category)
                    if rows.isEmpty {
                        EmptyStateView(
                            icon: "checkmark.seal",
                            title: "该分类下没有可清理项",
                            subtitle: "尝试调低筛选阈值或重新扫描。"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, AppSpacing.xl)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { _, node in
                        if let sub = node as? ScanSubCategory {
                            AppRowView(viewModel: viewModel, sub: sub)
                        }
                    }
                    if viewModel.remainingSubcategoryCount(in: category) > 0 {
                        RowCapFooterView(
                            remaining: viewModel.remainingSubcategoryCount(in: category),
                            onLift: { viewModel.capLiftedIDs.insert(category.id) }
                        )
                    }
                }
                .padding(AppSpacing.md)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Text(category.title)
                    .font(AppFont.title3)
                    .foregroundStyle(Color.textPrimary)
                Text(CategoryCardView.formatBytes(category.totalSize))
                    .font(AppFont.monoDigit)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Button("全选") { viewModel.selectAll(in: category) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("清空") { viewModel.deselectAll(in: category) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            HStack {
                TextField("搜索应用…", text: $viewModel.categoryQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Spacer()
                Toggle("显示过滤项", isOn: $viewModel.showAllHidden)
                    .toggleStyle(.checkbox)
                    .font(AppFont.caption)
            }
        }
        .padding(AppSpacing.md)
    }
}

// MARK: - App row (level 2)

private struct AppRowView: View {
    @ObservedObject var viewModel: ScanResultsViewModel
    let sub: ScanSubCategory

    @State private var appIcon: NSImage?

    private var isExpanded: Bool { viewModel.expandedAppIDs.contains(sub.id) }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(KFAnimation.easeInOut) {
                    viewModel.toggleExpandApp(sub.id)
                }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Button {
                        viewModel.toggleSelect(sub)
                    } label: {
                        IndeterminateCheckbox(state: sub.state)
                    }
                    .buttonStyle(.plain)
                    appIconView
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(displayTitle)
                            .font(AppFont.body)
                            .foregroundStyle(Color.textPrimary)
                        if !isPseudo, let bundleID = sub.bundleID {
                            Text(bundleID)
                                .font(AppFont.caption)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer()
                    RiskBadge(level: sub.riskLevel)
                    Text(CategoryCardView.formatBytes(sub.totalSize))
                        .font(AppFont.monoDigit)
                        .foregroundStyle(Color.textPrimary)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 2) {
                    let files = viewModel.visibleFiles(in: sub)
                    ForEach(Array(files.enumerated()), id: \.element.id) { _, file in
                        FileRowView(viewModel: viewModel, node: file)
                    }
                    // Flatten one more level when the action tier sits between
                    // the app row and its files (showAction buckets).
                    if files.isEmpty, !sub.actions.isEmpty {
                        let actionFiles = sub.actions.flatMap { $0.results.map { $0 as any ScanTreeNode } }
                        ForEach(Array(actionFiles.prefix(20).enumerated()), id: \.element.id) { _, file in
                            FileRowView(viewModel: viewModel, node: file)
                        }
                    }
                    if viewModel.remainingFileCount(in: sub) > 0 {
                        RowCapFooterView(
                            remaining: viewModel.remainingFileCount(in: sub),
                            onLift: { viewModel.capLiftedIDs.insert(sub.id) }
                        )
                    }
                }
                .padding(.leading, AppSpacing.xl)
                .padding(.bottom, AppSpacing.sm)
            }
        }
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .task(id: sub.bundleID) {
            appIcon = await Self.icon(forBundleID: sub.bundleID, pseudo: sub.isPseudoApp)
        }
    }

    private var isPseudo: Bool { sub.isPseudoApp }
    private var displayTitle: String { sub.appName ?? sub.title }

    @ViewBuilder
    private var appIconView: some View {
        if let appIcon {
            Image(nsImage: appIcon)
                .resizable()
        } else {
            Image(systemName: isPseudo ? "folder" : "app")
                .font(.system(size: 14))
                .foregroundStyle(Color.brandPrimary)
        }
    }

    /// App icon resolved off-main once per row (never in `body`).
    private static func icon(forBundleID bundleID: String?, pseudo: Bool) async -> NSImage? {
        guard !pseudo, let bundleID else { return nil }
        return await Task.detached(priority: .utility) { () -> NSImage? in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            else { return nil }
            return NSWorkspace.shared.icon(forFile: url.path)
        }.value
    }
}

// MARK: - File row (level 3)

struct FileRowView: View {
    @ObservedObject var viewModel: ScanResultsViewModel
    let node: any ScanTreeNode

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Button {
                viewModel.toggleSelect(node)
            } label: {
                IndeterminateCheckbox(state: node.state)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.title)
                    .font(AppFont.callout)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let result = node as? ScanResult {
                    Text(ScanTreeRow.friendlyPath(for: result.path))
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(result.path)  // C-1: raw path is tooltip-only
                }
            }
            Spacer()
            RiskBadge(level: node.riskLevel)
            Text(CategoryCardView.formatBytes(node.totalSize))
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.selectDetail(node.id) }
    }
}

// MARK: - Cap footer

struct RowCapFooterView: View {
    let remaining: Int
    let onLift: () -> Void

    var body: some View {
        Button {
            onLift()
        } label: {
            Text("显示其余 \(remaining) 项（按大小）")
                .font(AppFont.caption)
                .foregroundStyle(Color.brandPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.sm)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - VM extensions used by the master-detail surface

extension ScanResultsViewModel {
    /// Focuses the detail column on a category.
    func focus(_ category: ScanCategory) {
        focusedCategoryID = category.id
        categoryQuery = ""
    }

    /// Row tap → toggle the inline file list for an app bucket.
    func toggleExpandApp(_ id: UUID) {
        if expandedAppIDs.contains(id) {
            expandedAppIDs.remove(id)
        } else {
            expandedAppIDs.insert(id)
        }
    }

    /// 全选 scoped to ONE category — other categories are untouched
    /// (the old selectAll() flipped the entire tree).
    func selectAll(in category: ScanCategory) {
        category.setState(.checked)
        refreshAncestorsIfNeeded(category)
        refreshSummary(forCategory: category.id)
    }

    /// 清空 scoped to ONE category.
    func deselectAll(in category: ScanCategory) {
        category.setState(.unchecked)
        refreshAncestorsIfNeeded(category)
        refreshSummary(forCategory: category.id)
    }

    private func refreshAncestorsIfNeeded(_ category: ScanCategory) {
        // Categories have no ancestors; the summary refresh above suffices.
        _ = category
    }
}

// MARK: - Hover shadow helper

/// Conditional hover shadow — `appShadow` takes a non-optional token, so the
/// inactive case wraps a plain view.
struct HoverShadowModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.appShadow(AppShadow.sm)
        } else {
            content
        }
    }
}
