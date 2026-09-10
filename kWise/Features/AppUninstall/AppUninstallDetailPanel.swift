// kWise/Features/AppUninstall/AppUninstallDetailPanel.swift
//
// 卸载右侧详情面板 (v2.6 Task 4)：健康摘要卡 + AI 语义分组卡 + 动作栏。
// 三段布局见 spec §7 —— 摘要卡（顶部）→ 分组卡列表（滚动）→ 动作栏（底部）。
import SwiftUI
import AppKit
import DesignSystem
import CommonUtils
import AppCatalogCore

// MARK: - Detail Panel

/// 双栏右侧面板：选中条目的健康摘要、残留语义分组与动作入口。
/// 未选中任何条目时显示引导空态。
struct AppUninstallDetailPanel: View {
    @ObservedObject var viewModel: AppUninstallViewModel

    /// 由宿主视图接线（确认弹窗 / 配额路由仍归 AppUninstallView 所有）。
    var onUninstall: ((UninstallAppEntry) -> Void)? = nil

    /// 分组 >50ms 才亮骨架：快速路径（纯规则命中）不闪加载态。
    @State private var showGroupingSkeleton = false

    var body: some View {
        Group {
            if let entry = viewModel.selectedEntry {
                detail(for: entry)
            } else {
                EmptyStateView(
                    icon: "sidebar.right",
                    title: "选择一个应用查看详情",
                    subtitle: "在左侧列表点击任意应用，查看健康摘要与残留分组"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
    }

    // MARK: Three-Section Layout

    private func detail(for entry: UninstallAppEntry) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    HealthSummaryCard(entry: entry)
                    groupingArea(for: entry)
                }
                .padding(AppSpacing.lg)
            }

            Divider()
            DetailActionBar(entry: entry, viewModel: viewModel, onUninstall: onUninstall)
        }
    }

    // MARK: Grouping Area

    @ViewBuilder
    private func groupingArea(for entry: UninstallAppEntry) -> some View {
        let groups = viewModel.groupedResiduesForSelectedEntry()

        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("残留分组")
                .font(AppFont.title3)
                .foregroundColor(.textPrimary)

            if viewModel.groupingDegraded {
                Label(
                    "语义分组降级：系统词向量不可用，未识别路径已归入「其他」",
                    systemImage: "info.circle"
                )
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
            }

            if let groups {
                if groups.isEmpty {
                    Text("未发现残留文件")
                        .font(AppFont.callout)
                        .foregroundColor(.textSecondary)
                        .padding(.vertical, AppSpacing.md)
                } else {
                    ForEach(groups) { group in
                        ResidueGroupCard(
                            entry: entry,
                            group: group,
                            viewModel: viewModel
                        )
                    }
                }
            } else if showGroupingSkeleton {
                GroupingSkeleton()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: entry.id) {
            // 50ms 阈值：分组完成快于阈值则骨架一帧都不出现。
            // 骨架数据源 = 分组缓存是否落位（isGrouping 在 body 求值期
            // 间不可同步发布）。
            showGroupingSkeleton = false
            try? await Task.sleep(nanoseconds: 50_000_000)
            if !Task.isCancelled,
               viewModel.groupedResidues[entry.id] == nil,
               !entry.residues.isEmpty {
                showGroupingSkeleton = true
            }
        }
    }
}

// MARK: - Health Summary Card

/// 健康摘要卡（spec §7 第一段）：可解释评级 + 关键事实行。
private struct HealthSummaryCard: View {
    let entry: UninstallAppEntry

    private var summary: HealthSummary { HealthSummaryBuilder.build(for: entry) }

    private var gradeColor: Color {
        switch summary.grade {
        case .clean: return .success
        case .normal: return .warning
        case .bloated: return .danger
        }
    }

    /// 孤儿条目专属摘要行（App 本体不存在 → 无安装时长/最近使用）。
    private var orphanText: String {
        "应用已删除，仅剩残留 \(FileSizeFormatter.abbreviated(from: entry.leftoverSize))"
    }

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.appURL.path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)

                    Text(entry.appName)
                        .font(AppFont.title3)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text(summary.gradeText)
                        .font(AppFont.caption)
                        .foregroundColor(gradeColor)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 2)
                        .background(gradeColor.opacity(0.14))
                        .clipShape(Capsule())
                        .accessibilityLabel("健康评级：\(summary.gradeText)")
                }

                Divider()

                if entry.isOrphan {
                    Label(orphanText, systemImage: "trash")
                        .font(AppFont.callout)
                        .foregroundColor(.warning)
                } else {
                    factRow(icon: "calendar", label: "安装时长",
                            value: summary.daysInstalled.map { "\($0) 天" } ?? "未知")
                    factRow(icon: "clock", label: "使用情况", value: summary.lastUsedText)
                    factRow(icon: "internaldrive", label: "占用空间",
                            value: "\(summary.totalSizeText)（残留占比 \(Int((summary.residueRatio * 100).rounded()))%）")
                }
            }
            .padding(AppSpacing.md)
        }
    }

    private func factRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
                .frame(width: 16)
            Text(label)
                .font(AppFont.callout)
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(AppFont.callout)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
        }
    }
}

// MARK: - Residue Group Card

/// 单个语义分组卡（spec §7 第二段）：组头（图标/标题/级联勾选）+
/// 组内残留行（白话解释 + 友好路径）。C-1：raw path 仅 tooltip。
private struct ResidueGroupCard: View {
    let entry: UninstallAppEntry
    let group: ResidueGroup
    @ObservedObject var viewModel: AppUninstallViewModel

    @State private var isExpanded = true

    /// Reset 只清 preferences/caches/httpStorage/savedState —— 对应分组
    /// kinds 在组卡上直接标注「Reset 会清理此组」（spec §7）。
    private static let resettableKinds: Set<ResidueGroupKind> = [.preferences, .caches, .savedState]

    private var selectedPaths: Set<String> {
        viewModel.selectedResiduePaths[entry.id] ?? []
    }

    private var groupPaths: Set<String> {
        Set(group.residues.map { $0.url.path })
    }

    private var checkState: CheckState {
        let hit = groupPaths.intersection(selectedPaths)
        if hit.isEmpty { return .off }
        return hit.count == groupPaths.count ? .on : .mixed
    }

    private var groupSize: Int64 {
        group.residues.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        GlassPanel {
            VStack(spacing: 0) {
                // Group header — cascade checkbox + identity + size.
                HStack(spacing: AppSpacing.sm) {
                    // Cascade checkbox is its own button so toggling the
                    // group never collapses the card.
                    Button {
                        toggleGroup()
                    } label: {
                        IndeterminateCheckbox(state: checkState, size: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(group.kind.title) 全选")

                    Button {
                        withAnimation(.easeInOut(duration: KFAnimation.durationFast)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: group.kind.icon)
                                .font(AppFont.callout)
                                .foregroundColor(.brandPrimary)
                                .frame(width: 18)

                            Text(group.kind.title)
                                .font(AppFont.title3)
                                .foregroundColor(.textPrimary)

                            Text("\(group.residues.count) 项 · \(FileSizeFormatter.abbreviated(from: groupSize))")
                                .font(AppFont.caption)
                                .foregroundColor(.textSecondary)

                            if Self.resettableKinds.contains(group.kind) {
                                Text("Reset 会清理此组")
                                    .font(AppFont.caption)
                                    .foregroundColor(.brandSecondary)
                                    .padding(.horizontal, 5)
                                    .background(Color.brandSecondary.opacity(0.12))
                                    .clipShape(Capsule())
                            }

                            Spacer()

                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .font(AppFont.caption)
                                .foregroundColor(.textSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if isExpanded {
                    Divider()
                        .padding(.vertical, AppSpacing.xs)
                    ForEach(group.residues) { residue in
                        ResidueRow(
                            entry: entry,
                            residue: residue,
                            isSelected: selectedPaths.contains(residue.url.path),
                            viewModel: viewModel
                        )
                    }
                }
            }
            .padding(AppSpacing.sm)
        }
    }

    private func toggleGroup() {
        let allSelected = checkState == .on
        viewModel.setGroupSelection(
            entryID: entry.id, residues: group.residues, selected: !allSelected
        )
    }
}

// MARK: - Residue Row

/// 组内残留行：白话解释（ResidueExplainer）+ 友好路径显示。
/// C-1 路径规则与 DuplicateView 一致 —— 界面只显示友好路径，raw 仅 tooltip。
private struct ResidueRow: View {
    let entry: UninstallAppEntry
    let residue: ResidueFile
    let isSelected: Bool
    @ObservedObject var viewModel: AppUninstallViewModel

    private var explanation: String {
        ResidueExplainer.explain(residue, appName: entry.appName)
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { _ in
                    viewModel.toggleResidue(entryID: entry.id, path: residue.url.path)
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            KWThumbnailView(url: residue.url, size: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(ScanTreeRow.friendlyPath(for: residue.url.path))
                    .font(AppFont.callout)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    // C-1: raw path is tooltip-only.
                    .help(residue.url.path)

                Text(explanation)
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(residue.sizeFormatted)
                .font(AppFont.monoDigit)
                .foregroundColor(.textSecondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityHint(explanation)
    }
}

// MARK: - Grouping Skeleton

/// 「分析中…」骨架（分组计算 >50ms 时显示）。
private struct GroupingSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("分析中…")
                    .font(AppFont.callout)
                    .foregroundColor(.textSecondary)
            }
            // 复用共享骨架行（shimmer 脉冲、Reduce Motion 友好）。
            ForEach(0..<3, id: \.self) { _ in
                SkeletonRow()
            }
        }
        .accessibilityLabel("正在分析残留分组")
    }
}

// MARK: - Action Bar

/// 动作栏（spec §7 第三段）：卸载 / App Reset / 备份说明。
/// 孤儿条目无「卸载」（App 本体已不存在）→ 只有「清理残留」入口。
private struct DetailActionBar: View {
    let entry: UninstallAppEntry
    @ObservedObject var viewModel: AppUninstallViewModel
    var onUninstall: ((UninstallAppEntry) -> Void)?

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Label("残留先备份 30 天，可从备份还原", systemImage: "clock.arrow.circlepath")
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
                .lineLimit(1)

            Spacer()

            if entry.isOrphan {
                // 孤儿：无可卸载本体，仅清理残留（选中语义由宿主闭包处理）。
                Button("清理残留") {
                    onUninstall?(entry)
                }
                .buttonStyle(.borderedProminent)
                .tint(.danger)
            } else {
                Button {
                    Task { try? await viewModel.resetApp(entry) }
                } label: {
                    Label("App Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .help("保留应用，只清偏好与缓存类残留")

                Button {
                    onUninstall?(entry)
                } label: {
                    Label("卸载", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.danger)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
    }
}
