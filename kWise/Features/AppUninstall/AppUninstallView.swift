// kWise/Features/AppUninstall/AppUninstallView.swift
//
// 应用卸载 surface（M5）。引擎（Scanner / VM / ResidueGrouping /
// HealthSummary / 备份回滚）自 v2.0 Phase 2 与 v2.6 深度打磨交付，UI 随
// P2 T9 工具表面退役 —— 本视图按 ShredderView sheet 模式重建：
// 「+」菜单入口 → 列表 + 右侧残留详情双栏 → 确认弹窗 → 统一清理链
// （CleanupEngine：30 天历史 + 回滚 + 买断门），本文件零绕过。
//
// 红线（沿用 VM 契约）：确认弹窗的数字 = `selectedCommitSize` /
// `selectedCommitResidueCount`（实际提交范围，与执行同口径）；孤儿条目
// 只提交残留；配额拒绝 ≠ 卸载成功（引擎 skippedForQuota → 失败名单 +
// Paywall 路由）。
import SwiftUI
import UniformTypeIdentifiers
import CommonUtils
import DesignSystem

struct AppUninstallView: View {
    @StateObject private var viewModel: AppUninstallViewModel
    @State private var showConfirm = false
    @State private var resultBanner: String?
    @State private var isDropTargeted = false

    /// Injectable VM for previews/tests; the sheet host passes the graph
    /// cached instance (RootView `graph.appUninstallVM { … }`).
    init(viewModel: AppUninstallViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? AppUninstallViewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            if let resultBanner {
                Divider()
                resultRow
            }
        }
        .background(Color.bgPrimary)
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            if viewModel.entries.isEmpty, !viewModel.isScanning {
                viewModel.startScan()
            }
        }
        .confirmationDialog(
            confirmTitle,
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: String.LocalizationValue("uninstall.confirm.moveTrash")), role: .destructive) {
                showConfirm = false
                Task { await runUninstall() }
            }
            Button(String(localized: String.LocalizationValue("common.cancel")), role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(String(localized: String.LocalizationValue("uninstall.title")))
                    .font(AppFont.title2)
                    .foregroundStyle(Color.textPrimary)
                Text(String(localized: String.LocalizationValue("uninstall.subtitle")))
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Picker(String(localized: String.LocalizationValue("uninstall.sort.label")), selection: Binding(
                get: { viewModel.sortBy },
                set: { viewModel.toggleSort($0) })) {
                ForEach(AppUninstallViewModel.SortField.allCases, id: \.self) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)
            Button {
                viewModel.startScan()
            } label: {
                Label(String(localized: String.LocalizationValue("common.rescan")), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isScanning)
        }
        .padding(AppSpacing.lg)
    }

    // MARK: - Content（列表 + 详情双栏）

    @ViewBuilder
    private var content: some View {
        if viewModel.isScanning && viewModel.entries.isEmpty {
            scanningState
        } else if viewModel.entries.isEmpty {
            emptyState
        } else {
            HSplitView {
                listColumn
                    .frame(minWidth: 300, maxWidth: 420)
                detailColumn
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var scanningState: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
                .controlSize(.large)
            Text(String(localized: String.LocalizationValue("uninstall.scanning")))
                .font(AppFont.callout)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 36))
                .foregroundStyle(Color.textSecondary)
            Text(String(localized: String.LocalizationValue("uninstall.empty.title")))
                .font(AppFont.title3)
                .foregroundStyle(Color.textPrimary)
            Text(String(localized: String.LocalizationValue("uninstall.empty.subtitle")))
                .font(AppFont.callout)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDropTargeted ? Color.brandPrimary.opacity(0.08) : Color.clear)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var listColumn: some View {
        VStack(spacing: 0) {
            // 搜索 + 汇总行
            HStack(spacing: AppSpacing.sm) {
                TextField(String(localized: String.LocalizationValue("uninstall.search.placeholder")), text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Spacer()
                Text(String(format: String(localized: String.LocalizationValue("uninstall.count.apps")), viewModel.visibleEntries.count))
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)

            List(viewModel.visibleEntries, selection: $viewModel.selectedEntryID) { entry in
                listRow(entry)
            }
            .listStyle(.sidebar)

            // 底部提交行
            Divider()
            HStack {
                Text(commitSummary)
                    .font(AppFont.callout)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button(String(localized: String.LocalizationValue("uninstall.button.uninstallSelected"))) { showConfirm = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.danger)
                    .controlSize(.small)
                    .disabled(viewModel.selectedEntries.isEmpty)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
        }
    }

    private func listRow(_ entry: UninstallAppEntry) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Toggle(isOn: Binding(
                get: { entry.isSelected },
                set: { _ in viewModel.toggleSelection(entry.id) })) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppSpacing.xs) {
                    Text(entry.appName)
                        .font(AppFont.body)
                        .foregroundStyle(Color.textPrimary)
                    if entry.isOrphan {
                        Text(String(localized: String.LocalizationValue("uninstall.row.orphanBadge")))
                            .font(AppFont.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.warning.opacity(0.15))
                            .foregroundStyle(Color.warning)
                            .clipShape(Capsule())
                    }
                }
                Text(entry.bundleID)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(FileSizeFormatter.abbreviated(from: entry.totalSize))
                    .font(AppFont.monoDigit)
                    .foregroundStyle(Color.textPrimary)
                if entry.leftoverSize > 0 {
                    Text(String(format: String(localized: String.LocalizationValue("uninstall.row.leftover")), FileSizeFormatter.abbreviated(from: entry.leftoverSize)))
                        .font(AppFont.caption)
                        .foregroundStyle(Color.warning)
                }
            }
        }
        .tag(entry.id)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.selectedEntryID = entry.id }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let entry = viewModel.selectedEntry {
            AppUninstallDetailPanel(viewModel: viewModel, entry: entry)
        } else {
            VStack {
                Text(String(localized: String.LocalizationValue("uninstall.detail.placeholder")))
                    .font(AppFont.callout)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Result

    private var resultRow: some View {
        HStack {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Color.success)
            Text(resultBanner ?? "")
                .font(AppFont.callout)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Button(String(localized: String.LocalizationValue("common.ok"))) { resultBanner = nil }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .background(Color.bgSecondary)
    }

    // MARK: - Commit copy（与 VM 提交口径一致）

    private var commitSummary: String {
        let count = viewModel.selectedEntries.count
        guard count > 0 else {
            return String(localized: String.LocalizationValue("uninstall.commit.none"))
        }
        return String(
            format: String(localized: String.LocalizationValue("uninstall.commit.summary")),
            Int64(count), FileSizeFormatter.abbreviated(from: viewModel.selectedCommitSize))
    }

    private var confirmTitle: String {
        let entries = viewModel.selectedEntries
        let residues = viewModel.selectedPickedResidueCount
        if viewModel.hasExplicitResidueSelection && residues > 0 {
            return String(
                format: String(localized: String.LocalizationValue("uninstall.confirm.title.partial")),
                Int64(entries.count))
        }
        return String(
            format: String(localized: String.LocalizationValue("uninstall.confirm.title")),
            Int64(entries.count))
    }

    private var confirmMessage: String {
        let size = FileSizeFormatter.abbreviated(from: viewModel.selectedCommitSize)
        let residues = viewModel.selectedCommitResidueCount
        return String(
            format: String(localized: String.LocalizationValue("uninstall.confirm.message")),
            Int64(residues), size)
    }

    // MARK: - Actions

    private func runUninstall() async {
        let outcome = await viewModel.uninstallSelected()
        var parts: [String] = []
        if !outcome.succeeded.isEmpty {
            parts.append(String(
                format: String(localized: String.LocalizationValue("uninstall.result.uninstalled")),
                Int64(outcome.succeeded.count)))
        }
        if !outcome.failed.isEmpty {
            parts.append(String(
                format: String(localized: String.LocalizationValue("uninstall.result.failed")),
                Int64(outcome.failed.count)))
        }
        resultBanner = parts.isEmpty
            ? String(localized: String.LocalizationValue("uninstall.result.nothing"))
            : parts.joined(separator: "；")
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    await viewModel.importDraggedApp(at: url)
                }
            }
        }
        return true
    }
}
