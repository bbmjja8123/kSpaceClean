// kWise/Features/DetailPanel/DetailPanelView.swift
//
// 选中详情面板 (UX 重构 Phase 3) — replaces the three dead legacy tabs
// (概览/结果树/建议, all rendering a ScanViewModel that never scanned).
// Shows live context for the selected row: resolves the node through
// `ScanResultsViewModel.node(for:)` on every render, so cascade/selection
// changes can never go stale. Raw paths stay tooltip-only (C-1).
import SwiftUI
import AppKit
import DesignSystem

struct DetailPanelView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var viewModel: ScanResultsViewModel

    var body: some View {
        Group {
            if let selection = appState.detailSelection,
               let node = viewModel.node(for: selection.nodeID) {
                content(for: selection.kind, node: node)
            } else {
                // Stale selection (node removed by a filter re-apply) —
                // clear it so the panel hides next frame.
                Color.clear.onAppear { appState.detailSelection = nil }
            }
        }
    }

    @ViewBuilder
    private func content(for kind: AppState.DetailSelection.Kind,
                         node: any ScanTreeNode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                header(node)
                switch kind {
                case .category:
                    if let category = node as? ScanCategory {
                        categoryBody(category)
                    }
                case .app:
                    if let sub = node as? ScanSubCategory {
                        appBody(sub)
                    }
                case .file:
                    if let result = node as? ScanResult {
                        fileBody(result)
                    }
                }
            }
            .padding(AppSpacing.md)
        }
        .background(Color.bgSecondary)
    }

    // MARK: - Header

    private func header(_ node: any ScanTreeNode) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(node.title)
                    .font(AppFont.title3)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Spacer()
                RiskBadge(level: node.riskLevel)
            }
            Text(Self.formatBytes(node.totalSize))
                .font(AppFont.monoDigit)
                .foregroundStyle(Color.brandPrimary)
        }
        .padding(.bottom, AppSpacing.xs)
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(AppFont.callout)
                .foregroundStyle(Color.textPrimary)
                .textSelection(.enabled)
            Spacer()
        }
    }

    // MARK: - App detail

    private func appBody(_ sub: ScanSubCategory) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                metadataRow("已选", "\(Self.formatBytes(sub.selectedSize)) · \(stateLabel(sub.state))")
                if let bundleID = sub.bundleID {
                    metadataRow("标识", bundleID)
                }
                let fileCount = sub.actions.reduce(0) { $0 + $1.results.count } + sub.directResults.count
                metadataRow("文件数", "\(fileCount)")
                if sub.isPseudoApp {
                    metadataRow("类型", "未识别应用目录（按文件夹归组）")
                }
            }

            Divider()

            // Per-action breakdown — what the old tree's action tier hid
            // behind a second expansion.
            if !sub.actions.isEmpty {
                Text("构成")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
                ForEach(sub.actions) { action in
                    HStack {
                        RiskBadge(level: action.riskLevel, compact: true)
                        Text(action.title)
                            .font(AppFont.callout)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(Self.formatBytes(action.totalSize))
                            .font(AppFont.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Category detail

    private func categoryBody(_ category: ScanCategory) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                metadataRow("已选", "\(Self.formatBytes(category.selectedSize)) · \(stateLabel(category.state))")
                metadataRow("应用数", "\(category.subItems.count)")
                let fileCount = category.subItems.reduce(0) {
                    $0 + $1.actions.reduce(0) { $0 + $1.results.count } + $1.directResults.count
                }
                metadataRow("文件数", "\(fileCount)")
            }

            Divider()

            Text("占用最多")
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
            ForEach(category.subItems.sorted { $0.totalSize > $1.totalSize }.prefix(5)) { sub in
                HStack {
                    Text(sub.appName ?? sub.title)
                        .font(AppFont.callout)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(Self.formatBytes(sub.totalSize))
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    // MARK: - File detail

    private func fileBody(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                // C-1: friendly path is the visible line; the raw path is
                // tooltip + text-selection only.
                metadataRow("位置", ScanTreeRow.friendlyPath(for: result.path ?? ""))
                if let modified = result.modificationDate {
                    metadataRow("修改于", Self.relativeDate.localizedString(for: modified, relativeTo: Date()))
                }
                metadataRow("类型", cleanTypeLabel(result.cleanType))
            }
            if result.cautionID != nil {
                Text("该项涉及应用配置或个人数据，清理前请确认对应应用未在运行。")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.warning)
                    .padding(AppSpacing.sm)
                    .background(Color.warning.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
            }
        }
    }

    // MARK: - Helpers

    private func stateLabel(_ state: CheckState) -> String {
        switch state {
        case .checked, .on: return "已全选"
        case .mixed: return "部分已选"
        case .unchecked, .off: return "未选择"
        }
    }

    private func cleanTypeLabel(_ type: CleanType) -> String {
        switch type {
        case .cache: return "缓存"
        case .log: return "日志"
        case .preference: return "配置"
        case .database: return "数据库"
        case .temporary: return "临时文件"
        case .history: return "历史记录"
        case .cookie: return "Cookie"
        case .attachment: return "附件"
        case .binary: return "二进制"
        case .language: return "语言包"
        case .savedState: return "应用状态"
        case .snapshot: return "本地快照"
        case .keychain: return "钥匙串"
        }
    }

    static let relativeDate: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}
