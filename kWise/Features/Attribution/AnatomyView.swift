// kWise/Features/Attribution/AnatomyView.swift
//
// 主画布（P2 T3 重构，spec §3 解剖画布）：「你的 NNN GB，去哪了」。
// 结构（自上而下）：hero（idle=标题+构成条+按钮行；scanning=进度条+当前路径
// +取消，两态切换见 AnatomyScanState.swift 的 ScanPhase）→ DiskHealthCard →
// 扫描未覆盖卡（P0 黑盒卡的诚实版）→ CanvasGroupCard 动态组列表（找到才出现，
// 扫描中 opacity(0.4) 不清空）→ 系统状态条（T5 前静态占位）→ 拒答虚线卡
// （refused+probable）→ 规则链接。
// 红线：本页没有任何清理动作——组头「就地清理」只触发注入的回调（T5 接
// 预演链），hero「安全快捷回收」跳 Smart Care 次级页；扫描入口是 startScan
// （扇出 coordinator）。
// P0/P1 诚实渲染契约原样保留：空参数 lastModified 行隐藏、ruleID==nil 无
// notes、snapshots==nil → unreadable 行、.negativeResidual → insufficient。
import SwiftUI
import DesignSystem
import CommonUtils
import Combine

/// 一个原因分组：组内条目按 bytes 降序，组间按 totalBytes 降序（VM 保证）。
/// （P2 T3 起主画布渲染改走 CanvasGroup/CanvasReport；本类型保留供
/// `groupedSections` 的既有测试契约与归因叙事使用。）
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

    // MARK: 主画布扫描态（P2 T3 —— 实现/动作见 AnatomyScanState.swift 扩展）

    /// 最近一次画布扇出扫描的完成态报告（nil = 尚未完成过一次扇出扫描）。
    /// 读取 public、写入 module 内（AnatomyScanState.swift 的扩展方法）。
    @Published public internal(set) var canvasReport: CanvasReport?
    /// hero 扫描进度态（idle / scanning(progress, path) / done）。
    @Published public internal(set) var scanPhase: AnatomyViewModel.ScanPhase = .idle
    /// 画布扇出协调器（bindCoordinator 晚绑定）。
    var canvasCoordinator: CanvasScanCoordinator?
    /// 扫描范围覆盖（rebindScope 注入；nil = 走 defaultScope）。
    var canvasScopeProvider: (() -> CanvasScanScope)?
    /// 进行中的扇出 Task（startScan/cancelScan 操纵）。
    var canvasScanTask: Task<Void, Never>?
    /// coordinator 增量组/进度订阅。
    var canvasCancellables: Set<AnyCancellable> = []
    /// bindScanViewModel 的引擎进度/完成订阅（独立订阅集，重复 bind 不互扰）。
    var scanVMBindCancellables: Set<AnyCancellable> = []
    /// 引擎扫描镜像中（hero 进度条数据源 = ScanResultsViewModel.$progress）。
    var engineScanMirrored = false

    private let service: AttributionService
    /// internal：AnatomyScanState.swift 的扩展（runCanvasScan 完成后的
    /// 归因刷新）需要读取 provider。
    var categoriesProvider: (() -> [ScanCategory])?

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

    /// report.refused → 虚线卡数据 —— `coordinator.uncertainCard` 被扫描重置
    /// 为 nil 时的回退（画布不清空契约：上次结果保留变灰）。
    var reportUncertainCard: UncertainCard? {
        guard let report else { return nil }
        return CanvasGroupAssembler.uncertainCard(from: report.refused)
    }
}

public struct AnatomyView: View {
    @StateObject private var viewModel: AnatomyViewModel
    @ObservedObject private var diskHealthViewModel: DiskHealthViewModel
    /// 扇出协调器（增量组/诊断/虚线卡的 @Published 来源）。
    @ObservedObject private var coordinator: CanvasScanCoordinator
    @State private var rulesCorpus: AttributionRuleCorpus?
    private let onQuickClean: () -> Void
    private let onOpenDiskHealth: () -> Void
    /// 组头「就地清理」回调 —— T5 接组过滤预演链；本任务注入空实现
    /// （视图零清理动作，Global Constraints）。
    private let onGroupAction: (CanvasGroup) -> Void

    init(viewModel: AnatomyViewModel,
         coordinator: CanvasScanCoordinator,
         diskHealthViewModel: DiskHealthViewModel,
         onQuickClean: @escaping () -> Void,
         onOpenDiskHealth: @escaping () -> Void,
         onGroupAction: @escaping (CanvasGroup) -> Void = { _ in }) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.coordinator = coordinator
        self.diskHealthViewModel = diskHealthViewModel
        self.onQuickClean = onQuickClean
        self.onOpenDiskHealth = onOpenDiskHealth
        self.onGroupAction = onGroupAction
    }

    public var body: some View {
        List {
            heroSection
            // P1 T9 — T6 遗留条件：DiskHealthCard 此前的唯一渲染位
            // （旧工具箱模块网格）已随 smartCare 降级删除；主画布的
            // 英雄头本就呈现卷状态，磁盘健康卡是这里的自然邻居。
            // 点击进入 DiskHealthDetailView。
            Section {
                DiskHealthCard(viewModel: diskHealthViewModel, onOpen: onOpenDiskHealth)
                    .frame(height: 120)
            }
            diagnosticsSection
            if let report = viewModel.report {
                uncoveredCard(report)
            } else {
                Section {
                    Text("attr.preview.empty")
                        .foregroundStyle(Color.textSecondary)
                }
            }
            groupsSection
            systemStatusSection
            uncertainSection
            rulesLink
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

    // MARK: - 英雄头（idle ↔ scanning 两态，spec §3.1 / §5）

    @ViewBuilder
    private var heroSection: some View {
        Section {
            if viewModel.scanPhase.isScanning {
                scanningHero
            } else {
                idleHero
            }
        }
    }

    /// idle 态：标题 + 副行 + 构成条 + 按钮行（快捷回收 · 「+」菜单占位 · 重新扫描）。
    private var idleHero: some View {
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
            compositionBar
            HStack(spacing: AppSpacing.sm) {
                // 唯一的回收入口：跳 Smart Care 次级页（T5 起改走预演链）。
                // 本页本身零清理动作。
                Button(action: onQuickClean) {
                    Text(quickCleanTitle)
                }
                .buttonStyle(.borderedProminent)
                // 「+」菜单占位 —— P2 T4 接 CanvasPlusMenu（粉碎窗/规则/维护）。
                Image(systemName: "plus.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.textSecondary)
                    .help(String(localized: String.LocalizationValue("canvas.hero.plusMenu.help")))
                Button {
                    viewModel.startScan()
                } label: {
                    Text("canvas.hero.rescan")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }

    /// 「安全快捷回收 · 预计 X」——估算只累计绿徽（✓ 可回收）条目的诚实字节；
    /// 无可回收字节时退回纯「安全快捷回收」文案（不显示「预计 0 B」）。
    private var quickCleanTitle: String {
        let estimate = viewModel.quickCleanEstimate
        guard estimate > 0 else {
            return String(localized: String.LocalizationValue("attr.anatomy.safeClean"))
        }
        return String(format: String(localized: String.LocalizationValue("canvas.hero.quickClean")),
                      FileSizeFormatter.abbreviated(from: estimate))
    }

    /// 构成条（spec §3.1）：按组着色、按 totalBytes 配比的分段条 —— 画布即地图。
    @ViewBuilder
    private var compositionBar: some View {
        let slices = viewModel.compositionSlices
        if !slices.isEmpty {
            HStack(spacing: 1) {
                ForEach(slices) { slice in
                    Capsule()
                        .fill(slice.color)
                        .frame(height: 6)
                        .layoutPriority(max(slice.fraction, 0.01))
                }
            }
        }
    }

    /// 扫描中态：进度条 + 当前路径 + 取消（spec §5）。progress 为 0（扇出
    /// 尚未产出第一组）时用不确定样式 —— 绝不显示静止的「0%」假象。
    private var scanningHero: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("canvas.scan.progress.title")
                .font(AppFont.title2)
            if case .scanning(let progress, let path) = viewModel.scanPhase {
                if progress > 0 {
                    ProgressView(value: min(max(progress, 0), 1))
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(path.isEmpty
                     ? String(localized: String.LocalizationValue("canvas.scan.preparing"))
                     : path)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(path)
            }
            Button {
                viewModel.cancelScan()
            } label: {
                Text("canvas.scan.cancel")
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    // MARK: - 扫描降级态行（T2 fix r1 诊断通道）

    @ViewBuilder
    private var diagnosticsSection: some View {
        if !coordinator.scanDiagnostics.isEmpty {
            Section(header: Text("canvas.diagnostic.title")) {
                ForEach(Array(coordinator.scanDiagnostics.enumerated()), id: \.offset) { _, message in
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Color.warning)
                        Text(message)
                            .font(AppFont.callout)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
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

    // MARK: - 动态组卡列表（找到才出现；扫描中变灰不清空，spec §5）

    @ViewBuilder
    private var groupsSection: some View {
        let groups = viewModel.displayGroups
        if !groups.isEmpty {
            Section {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    // 默认展开前 2 组（spec §3.4）；全量条目走 T6 下钻页。
                    CanvasGroupCard(group: group,
                                    initiallyExpanded: index < 2,
                                    onRehearse: onGroupAction)
                }
                .opacity(viewModel.scanPhase.isScanning ? 0.4 : 1)
                .disabled(viewModel.scanPhase.isScanning)
            }
        }
    }

    // MARK: - 系统状态条（spec §3.5 —— T5 前静态占位，不显示假数据）

    private var systemStatusSection: some View {
        Section {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "switch.2")
                    .foregroundStyle(Color.textSecondary)
                Text("canvas.systemStatus.placeholder")
                    .font(AppFont.callout)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    // MARK: - 拒答虚线卡（refused + probable，spec §3.6）

    @ViewBuilder
    private var uncertainSection: some View {
        // T2 的 coordinator.uncertainCard 优先；扫描开始时它被重置为 nil，
        // 此时回退 report 派生 —— 上一次结果保留，不清空。
        let card = coordinator.uncertainCard ?? viewModel.reportUncertainCard
        if let card {
            Section {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(String(
                        format: String(localized: String.LocalizationValue("attr.refused.title")),
                        card.items.count))
                        .font(AppFont.title3)
                    Text("attr.refused.banner")
                        .font(AppFont.callout)
                        .foregroundStyle(Color.textSecondary)
                    ForEach(card.items) { item in
                        anatomyRow(item)
                    }
                }
                .padding(AppSpacing.md)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.xl)
                        .strokeBorder(Color.separatorColor.opacity(0.8),
                                      style: StrokeStyle(lineWidth: 1, dash: [4]))
                )
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
