// kWise/Features/AppUninstall/AppUninstallDetailPanelView.swift
//
// 卸载列表右侧详情面板（v2.6 深度打磨产物的重建宿主）：健康摘要
// （HealthSummaryBuilder）、残留语义分组（ResidueGroupingEngine，规则遍 +
// NLEmbedding 兜底）、逐项解释（ResidueExplainer）与共享组件告警。
// 本面板只做「表达意图」—— 勾选写回 VM（per-entry 隔离），提交统一走
// 列表底部「卸载所选」→ 确认弹窗 → CleanupEngine（AppUninstallView）。
import SwiftUI
import AppCatalogCore
import CommonUtils
import DesignSystem

struct AppUninstallDetailPanel: View {
    @ObservedObject var viewModel: AppUninstallViewModel
    let entry: UninstallAppEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                headerSection
                if let warning = viewModel.sharedComponentWarning(for: entry) {
                    warningCard(warning)
                }
                residueSection
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.bgPrimary)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(entry.appName)
                .font(AppFont.title3)
                .foregroundStyle(Color.textPrimary)
            Text(entry.bundleID)
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)

            let summary = HealthSummaryBuilder.build(for: entry)
            HStack(spacing: AppSpacing.lg) {
                Label(summary.totalSizeText, systemImage: "internaldrive")
                Label(summary.lastUsedText, systemImage: "clock")
                if let days = summary.daysInstalled {
                    Label("已安装 \(days) 天", systemImage: "calendar")
                }
            }
            .font(AppFont.caption)
            .foregroundStyle(Color.textSecondary)
        }
    }

    private func warningCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.warning)
            Text(text)
                .font(AppFont.callout)
                .foregroundStyle(Color.textPrimary)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.warning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Residues

    @ViewBuilder
    private var residueSection: some View {
        if let groups = viewModel.groupedResiduesForSelectedEntry() {
            if groups.isEmpty {
                Text("该应用没有发现残留文件。")
                    .font(AppFont.callout)
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(groups) { group in
                    residueGroupCard(group)
                }
                if viewModel.groupingDegraded {
                    Label("语义分组降级（本机语义模型不可用），按路径规则分组。", systemImage: "info.circle")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        } else {
            // 分组计算中 —— 骨架行（VM 惰性计算 + 主线程发布）。
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.bgSecondary)
                        .frame(height: 18)
                }
            }
        }
    }

    private func residueGroupCard(_ group: ResidueGroup) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: group.kind.icon)
                    .foregroundStyle(Color.brandPrimary)
                Text(group.kind.title)
                    .font(AppFont.title3)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button(viewModel.groupSelected(entry.id, group.residues) ? "取消全组" : "全选") {
                    let selected = viewModel.groupSelected(entry.id, group.residues)
                    viewModel.setGroupSelection(entryID: entry.id,
                                                residues: group.residues,
                                                selected: !selected)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            ForEach(group.residues) { residue in
                residueRow(residue)
            }
        }
        .padding(AppSpacing.md)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func residueRow(_ residue: ResidueFile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AppSpacing.sm) {
                Toggle(isOn: Binding(
                    get: { viewModel.isResidueSelected(entry.id, residue) },
                    set: { _ in viewModel.toggleResidue(entryID: entry.id, path: residue.url.path) })) {
                    EmptyView()
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)

                Text(residue.url.path)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(FileSizeFormatter.abbreviated(from: residue.sizeBytes))
                    .font(AppFont.monoDigit)
                    .foregroundStyle(Color.textSecondary)
            }
            if !residue.description.isEmpty {
                Text(residue.description)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.leading, 22)
            }
        }
    }
}
