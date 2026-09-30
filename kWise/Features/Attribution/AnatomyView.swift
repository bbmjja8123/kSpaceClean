// kWise/Features/Attribution/AnatomyView.swift
//
// 解剖视图（spec §1.1 新首屏英雄）：「你的 NNN GB，去哪了」。
// 结构：英雄头（卷用量）→ 扫描未覆盖卡（P0 黑盒卡的诚实版）→ 按原因分组的
// 归因区（组内条目理由展开 + 置信度徽章）→ 推测区（L1）→ 拒答区 → 规则清单。
// 红线：本页没有任何清理动作——回收入口只有「安全快捷回收」（跳 SmartCare
// 次级页）与扫描页的预演流。
// 本文件整体替换并退役 P0 验证面 AttributionPreviewView（其已验证的诚实卡、
// 证据链渲染与拒答双源逻辑迁移至此，非复制——差异：英雄头 + 快捷回收按钮 +
// 原因分组 + 置信度徽章）。
import SwiftUI
import DesignSystem
import CommonUtils

/// 一个原因分组：组内条目按 bytes 降序，组间按 totalBytes 降序（VM 保证）。
public struct AnatomySection: Identifiable, Equatable {
    public let id: AttributionCause
    public let title: String
    public let totalBytes: Int64
    public let items: [SpaceAttribution]
}

@MainActor
public final class AnatomyViewModel: ObservableObject {
    @Published public private(set) var report: AttributionReport?
    @Published public private(set) var isLoading = false

    private let service: AttributionService
    private var categoriesProvider: (() -> [ScanCategory])?

    public init(service: AttributionService) { self.service = service }

    /// RootView 在 onAppear 注入（沿用 spaceMapViewModel.rebindRoots 模式）。
    public func rebindCategories(_ provider: @escaping () -> [ScanCategory]) {
        categoriesProvider = provider
    }

    public func refresh() async {
        guard let categoriesProvider, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        report = await service.attribute(categories: categoriesProvider())
    }

    public var usedBytes: Int64? { report?.blackBox.usedBytes }

    public var groupedSections: [AnatomySection] {
        let items = report?.items ?? []
        let grouped = Dictionary(grouping: items) { $0.cause }
        return grouped.map { cause, group in
            AnatomySection(id: cause,
                           title: AttributionCopy.causeLabel(cause),
                           totalBytes: group.reduce(0) { $0 + $1.bytes },
                           items: group.sorted { $0.bytes > $1.bytes })
        }.sorted { $0.totalBytes > $1.totalBytes }
    }

    /// L1 推测项（仍属拒答语义，但单独成区以「可能」措辞呈现）。
    public var probableItems: [SpaceAttribution] {
        (report?.refused ?? []).filter { $0.confidence == .probable }
            .sorted { $0.bytes > $1.bytes }
    }

    public var refusedItems: [SpaceAttribution] {
        (report?.refused ?? []).filter { $0.confidence != .probable }
            .sorted { $0.bytes > $1.bytes }
    }
}

public struct AnatomyView: View {
    @StateObject private var viewModel: AnatomyViewModel
    @ObservedObject private var diskHealthViewModel: DiskHealthViewModel
    @State private var rulesCorpus: AttributionRuleCorpus?
    private let onQuickClean: () -> Void
    private let onOpenDiskHealth: () -> Void

    init(viewModel: AnatomyViewModel,
         diskHealthViewModel: DiskHealthViewModel,
         onQuickClean: @escaping () -> Void,
         onOpenDiskHealth: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.diskHealthViewModel = diskHealthViewModel
        self.onQuickClean = onQuickClean
        self.onOpenDiskHealth = onOpenDiskHealth
    }

    public var body: some View {
        List {
            heroHeader
            // P1 T9 — T6 遗留条件：DiskHealthCard 此前的唯一渲染位
            // （旧工具箱模块网格）已随 smartCare 降级删除；解剖视图的
            // 英雄头本就呈现卷状态，磁盘健康卡是这里的自然邻居。
            // 点击进入 DiskHealthDetailView。
            Section {
                DiskHealthCard(viewModel: diskHealthViewModel, onOpen: onOpenDiskHealth)
                    .frame(height: 120)
            }
            if let report = viewModel.report {
                uncoveredCard(report)
                ForEach(viewModel.groupedSections) { section in
                    Section(header: Text(String(
                        format: String(localized: String.LocalizationValue("attr.anatomy.section")),
                        section.title, FileSizeFormatter.abbreviated(from: section.totalBytes)))) {
                        ForEach(section.items.prefix(20)) { item in
                            anatomyRow(item)
                        }
                    }
                }
                probableSection
                refusedSection
                rulesLink
            } else {
                Text("attr.preview.empty")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .navigationTitle(Text("nav.anatomy"))
        .toolbar {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Text("attr.preview.refresh")
            }
            .disabled(viewModel.isLoading)
        }
        .task {
            loadCorpusAndRefresh()
            await diskHealthViewModel.refresh()
        }
    }

    private func loadCorpusAndRefresh() {
        if rulesCorpus == nil {
            rulesCorpus = (Bundle.main.url(forResource: "attribution_rules",
                                           withExtension: "json"))
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { try? AttributionRuleCorpus.load(from: $0) }
        }
        Task { await viewModel.refresh() }
    }

    // MARK: - 英雄头

    private var heroHeader: some View {
        Section {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                if let used = viewModel.usedBytes {
                    Text(String(
                        format: String(localized: String.LocalizationValue("attr.anatomy.hero")),
                        FileSizeFormatter.abbreviated(from: used)))
                        .font(AppFont.title2)
                }
                Text("attr.anatomy.hero.subtitle")
                    .font(AppFont.callout)
                    .foregroundStyle(Color.textSecondary)
                // 唯一的回收入口：跳 Smart Care 次级页。本页本身零清理动作。
                Button(action: onQuickClean) {
                    Text("attr.anatomy.safeClean")
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, AppSpacing.xs)
        }
    }

    // MARK: - 扫描未覆盖卡（P0 final review I1 诚实版迁移）

    @ViewBuilder
    private func uncoveredCard(_ report: AttributionReport) -> some View {
        let breakdown = report.blackBox
        Section(header: Text("attr.blackbox.uncovered.title")) {
            switch breakdown.status {
            case .reconciled:
                Text(String(
                    format: String(localized: String.LocalizationValue("attr.blackbox.uncovered.body")),
                    FileSizeFormatter.abbreviated(from: breakdown.residualBytes)))
                if report.unattributedBytes > 0 {
                    Text(String(
                        format: String(localized: String.LocalizationValue("attr.blackbox.unattributed")),
                        FileSizeFormatter.abbreviated(from: report.unattributedBytes)))
                        .font(AppFont.callout)
                        .foregroundStyle(Color.textSecondary)
                }
                if breakdown.snapshotCount > 0 {
                    Text(String(
                        format: String(localized: String.LocalizationValue("attr.blackbox.snapshots")),
                        breakdown.snapshotCount))
                        .font(AppFont.callout)
                        .foregroundStyle(Color.textSecondary)
                }
            case .negativeResidual:
                // 残差为负说明口径对不上（如 purgeable 重复计入），此时没有任何
                // 可信数字 —— 诚实承认数据不足，绝不伪造「约 0 B」。
                Text("attr.blackbox.insufficient")
            case .insufficientData:
                Text("attr.blackbox.insufficient")
            }
            if report.snapshots == nil {
                Text("attr.blackbox.unreadable")
                    .font(AppFont.callout)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    // MARK: - 条目行（证据链迁移自 P0 attributionRow）

    @ViewBuilder
    private func anatomyRow(_ item: SpaceAttribution) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(AttributionCopy.reclaimLabel(item.reclaim))
                    .font(AppFont.callout)
                ForEach(Array(item.evidence.enumerated()), id: \.offset) { _, evidence in
                    // （P0 T5 审查裁定）证据链恒 4 元：`.lastModified` 在无日期时
                    // `arguments` 为空数组。此时 `attr.ev.lastModified` 的 %@ 会以
                    // 字面量露出（"最后修改 %@"）—— 渲染成空参数行属禁止项，
                    // 因此直接隐藏该行，不渲染占位文案。
                    if evidence.kind == .lastModified, evidence.arguments.isEmpty {
                        EmptyView()
                    } else {
                        Text(AttributionCopy.evidenceText(evidence))
                            .font(AppFont.callout)
                    }
                }
                // 拒答清单混有「规则不敢判」（ruleID 非 nil）与「未匹配大项」
                // （ruleID == nil）两种来源；notesText 对后者返回空串 —— 不渲染
                // 空 notes 行，即区分开两类条目。
                if !item.notesText.isEmpty {
                    Text(item.notesText)
                        .font(AppFont.callout)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AttributionCopy.ownerLabel(item.owner))
                        .font(AppFont.body)
                    Text(AttributionCopy.causeLabel(item.cause))
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                confidenceBadge(item.confidence)
                Text(FileSizeFormatter.abbreviated(from: item.bytes))
                    .font(AppFont.caption.monospaced())
            }
        }
    }

    /// 置信度徽章：规则命中 → 「规则判定」；模型推测 → 「推测（本地模型）」。
    @ViewBuilder
    private func confidenceBadge(_ confidence: AttributionConfidence) -> some View {
        switch confidence {
        case .probable:
            Text("attr.confidence.probable")
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
        case .certain:
            Text("attr.anatomy.badge.rule")
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
        case .refused:
            EmptyView()
        }
    }

    // MARK: - 推测区（L1）与拒答区

    /// L1 推测项：来源是本机模型（非规则），措辞用「可能」；依然不给清理建议。
    private var probableSection: some View {
        Group {
            if !viewModel.probableItems.isEmpty {
                Section(header: Text("attr.confidence.probable")) {
                    ForEach(viewModel.probableItems) { item in
                        anatomyRow(item)
                    }
                }
            }
        }
    }

    private var refusedSection: some View {
        Group {
            // 清单为空时整段折叠 —— 空 header 与「判断不了」横幅在无内容时
            // 都是噪音，且与事实不符（P0 T9 契约，迁移保持）。
            if !viewModel.refusedItems.isEmpty {
                Section(header: Text(String(
                    format: String(localized: String.LocalizationValue("attr.refused.title")),
                    viewModel.refusedItems.count))) {
                    Text("attr.refused.banner")
                        .font(AppFont.callout)
                        .foregroundStyle(Color.textSecondary)
                    ForEach(viewModel.refusedItems) { item in
                        anatomyRow(item)
                    }
                }
            }
        }
    }

    // MARK: - 规则清单

    @ViewBuilder
    private var rulesLink: some View {
        if let corpus = rulesCorpus {
            Section {
                NavigationLink {
                    AttributionRulesView(corpus: corpus)
                } label: {
                    Text("attr.rules.title")
                }
            }
        }
    }
}

extension SpaceAttribution {
    /// 行内展开的理由链尾行：规则 note（xcstrings key 装配）。
    /// key 必须先拼接再构造 LocalizationValue —— 插值写法会把 key 变成
    /// "attr.notes.%@"，查表必失配而渲染裸 key（P1 T4 review r1）。
    var notesText: String {
        guard let ruleID else { return "" }
        return String(localized: String.LocalizationValue("attr.notes." + ruleID))
    }
}
