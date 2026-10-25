// kWise/Features/Attribution/AnatomyView.swift
//
// 主画布（P2 T3 重构，spec §3 解剖画布）：「你的 NNN GB，去哪了」。
// 结构（自上而下）：hero（idle=标题+构成条+按钮行；scanning=进度条+当前路径
// +取消，两态切换见 AnatomyScanState.swift 的 ScanPhase）→ DiskHealthCard →
// 扫描未覆盖卡（P0 黑盒卡的诚实版）→ CanvasGroupCard 动态组列表（找到才出现，
// 扫描中 opacity(0.4) 不清空）→ 系统状态条（T5 前静态占位）→ 拒答虚线卡
// （refused+probable）→ 规则链接。
// 红线：本页没有任何清理动作——组头「就地清理」与 hero「安全快捷回收」
// 都只触发注入的回调（P2 T5 R-统一：RootView 把两者接进统一预演链 ——
// 组头 = 组过滤预演、hero = 推荐项预演，均由根部 CleanupRehearsalSheet
// 呈现）；扫描入口是 startScan（扇出 coordinator）。P2 T6：组卡点击区
// 进下钻页（GroupDrillDownView），下钻的「预演并清理」同样只回调勾选集
// （onDrillDownRehearse → 根部统一预演 sheet），本页仍零清理动作。
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
    /// C1（P2 final）：bindScanViewModel 绑定的扫描页 VM —— runCanvasScan
    /// 的统一入口先 await 它的引擎扫描完成，再对新鲜树做扇出。
    var scanVM: ScanResultsViewModel?

    private let service: AttributionService
    /// internal：AnatomyScanState.swift 的扩展（runCanvasScan 完成后的
    /// 归因刷新）需要读取 provider。
    var categoriesProvider: (() -> [ScanCategory])?
    /// T6 下钻 —— cause 树切片的归因引擎透出（GroupDrillDownSource 消费；
    /// 纯内存展开，不触文件系统）。
    var attributionEngine: AttributionRuleEngine { service.engine }
    /// T6 下钻 —— 节点问答（AssistantNodePanel）的数据源（RootView onAppear
    /// 晚绑定，同 rebindCategories 模式）。
    var scanResultsProvider: (() -> ScanResultsViewModel?)?
    /// T6 下钻 —— 勾选态 VM 缓存（GroupKind → VM）：面包屑返回后再进同一组
    /// 取回同一份实例，勾选原样保留。新扫描写 canvasReport 时整体作废
    /// （AnatomyScanState.runCanvasScan）。
    var drillDownModels: [GroupKind: GroupDrillDownModel] = [:]

    public init(service: AttributionService) { self.service = service }

    /// RootView 在 onAppear 注入（沿用 spaceMapViewModel.rebindRoots 模式）。
    public func rebindCategories(_ provider: @escaping () -> [ScanCategory]) {
        categoriesProvider = provider
    }

    /// RootView 在 onAppear 注入（T6 下钻页节点问答的数据源，同晚绑定模式）。
    func rebindScanResults(_ provider: @escaping () -> ScanResultsViewModel?) {
        scanResultsProvider = provider
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

    /// I2（P2 final）：就地清理成功后画布**就地失效** —— 不等下一次重扫：
    /// - 从 `canvasReport.groups` 移除已执行 targets 命中的条目（整组清空
    ///   则连组一起消失 —— 组装器「空组不出现」契约）；
    /// - 作废下钻勾选态缓存（旧组已不存在，陈旧勾选是假承诺）；
    /// - 重跑归因（纯内存，hero 构成条/未覆盖卡随新事实刷新）。
    public func applyCleanupOutcome(_ outcome: CleanupOutcome) async {
        let cleanedPaths = Set(outcome.succeeded.map(\.path))
        guard !cleanedPaths.isEmpty else { return }
        if let report = canvasReport {
            let groups = report.groups.compactMap { group -> CanvasGroup? in
                let remaining = group.entries.filter { entry in
                    guard let path = entry.target?.url.path else { return true }
                    return !cleanedPaths.contains(path)
                }
                guard remaining.count != group.entries.count else { return group }
                return CanvasGroupAssembler.assemble(
                    kind: group.id,
                    icon: group.icon,
                    title: group.title,
                    subtitle: group.subtitle,
                    action: group.action,
                    entries: remaining)
            }
            canvasReport = CanvasReport(groups: groups,
                                        uncovered: report.uncovered,
                                        snapshots: report.snapshots,
                                        generatedAt: Date())
        }
        drillDownModels.removeAll()
        await refresh()
    }
}

public struct AnatomyView: View {
    @StateObject private var viewModel: AnatomyViewModel
    @ObservedObject private var diskHealthViewModel: DiskHealthViewModel
    /// 扇出协调器（增量组/诊断/虚线卡的 @Published 来源）。
    @ObservedObject private var coordinator: CanvasScanCoordinator
    /// 快捷回收状态机（P2 T9 fix r1，Important 2）：hero 渲染其结果态
    /// （done/failed），执行与确认仍在根部统一预演链。
    @ObservedObject private var smartCareViewModel: SmartCareViewModel
    /// 授权快照（P2 T9 fix r1，Critical 1）：container-only 时快捷回收位
    /// 渲染授权卡，管线不允许启动。
    @ObservedObject private var appScope = AppScope.shared
    @State private var grantCardDismissed = false
    @State private var rulesCorpus: AttributionRuleCorpus?
    private let onQuickClean: () -> Void
    private let onOpenDiskHealth: () -> Void
    /// 组头「就地清理」回调 —— T5 接组过滤预演链；本任务注入空实现
    /// （视图零清理动作，Global Constraints）。
    private let onGroupAction: (CanvasGroup) -> Void
    /// 「+」菜单 → 粉碎窗（RootView 挂 sheet + 整窗拖放转发，P2 T4）。
    private let onOpenShredder: () -> Void
    /// 扫描中态「取消」回调（P2 T5 fix r1，Important 1）：扇出取消之外，
    /// RootView 据此把快捷回收管线一并作废 —— 否则取消后管线照样落
    /// `.confirming`，模态预演 sheet 会在用户明确取消后弹出。
    private let onScanCancelled: () -> Void
    /// 下钻页底部「预演并清理」（P2 T6）—— 勾选集条目（target + 徽章）→
    /// 根部统一预演 sheet（与组头就地清理同一张 sheet、同一条
    /// CleanupViewModel 链）。参数：组名（sheet 语境副行）+ 勾选集条目。
    private let onDrillDownRehearse: (String, [CanvasEntry]) -> Void
    /// 打开的下钻页（T6）：nil = 画布；非 nil = 下钻页替换画布区。
    /// 本 App 无 NavigationStack（导航全走 appState 切换），下钻用本地
    /// 页面切换实现「推入 → 面包屑返回」，勾选态由 VM 缓存跨页面保留。
    @State private var drillDown: DrillDownDestination?
    /// 归因规则 sheet（「+」菜单 rules 项；规则链接行的同一 corpus）。
    @State private var showRulesSheet = false

    /// 下钻目的地：组 + 打开时刻计算的条目切片（cause 组 = 树切片）。
    private struct DrillDownDestination: Equatable {
        let group: CanvasGroup
        let entries: [CanvasEntry]
    }

    init(viewModel: AnatomyViewModel,
         coordinator: CanvasScanCoordinator,
         diskHealthViewModel: DiskHealthViewModel,
         smartCareViewModel: SmartCareViewModel,
         onQuickClean: @escaping () -> Void,
         onOpenDiskHealth: @escaping () -> Void,
         onGroupAction: @escaping (CanvasGroup) -> Void = { _ in },
         onOpenShredder: @escaping () -> Void = {},
         onScanCancelled: @escaping () -> Void = {},
         onDrillDownRehearse: @escaping (String, [CanvasEntry]) -> Void = { _, _ in }) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.coordinator = coordinator
        self.diskHealthViewModel = diskHealthViewModel
        self.smartCareViewModel = smartCareViewModel
        self.onQuickClean = onQuickClean
        self.onOpenDiskHealth = onOpenDiskHealth
        self.onGroupAction = onGroupAction
        self.onOpenShredder = onOpenShredder
        self.onScanCancelled = onScanCancelled
        self.onDrillDownRehearse = onDrillDownRehearse
    }

    public var body: some View {
        if let drillDown {
            GroupDrillDownView(
                group: drillDown.group,
                entries: drillDown.entries,
                onRehearse: { entries in
                    onDrillDownRehearse(drillDown.group.title, entries)
                },
                onBack: { self.drillDown = nil },
                scanResultsProvider: viewModel.scanResultsProvider ?? { nil },
                selectionModel: viewModel.drillDownModel(
                    for: drillDown.group, entries: drillDown.entries))
        } else {
            canvasBody
        }
    }

    private var canvasBody: some View {
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
        // 规则清单 sheet 的唯一落点（M2）：规则链接行与「+」菜单 rules 项
        // 都走这里 —— 同一份已加载 corpus，同一张 AttributionRulesView。
        .sheet(isPresented: $showRulesSheet) {
            if let corpus = rulesCorpus {
                AttributionRulesView(corpus: corpus)
                    .frame(minWidth: 560, minHeight: 420)
            }
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
            } else if viewModel.scanPhase == .stopping {
                stoppingHero
            } else {
                idleHero
            }
        }
    }

    /// 「正在停止…」（I3，P2 final）：取消后上一轮管线收尾的诚实过渡态 ——
    /// 不伪造进度，也不给一个点了没反应的重扫按钮。
    private var stoppingHero: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("canvas.scan.stopping")
                .font(AppFont.title2)
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    /// idle 态：标题 + 副行 + 构成条 + 结果态卡（若有）+ 按钮行（快捷回收 ·
    /// 「+」菜单 · 重新扫描）。
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
            // fix r1（Important 2）：快捷回收结果态回到 hero —— done 显示
            // 真实释放字节（C-3）+「移入废纸篓 · 30 天可还原」披露行，
            // failed 显示失败信息；8 秒后自动复位，点「好」立即复位。
            if QuickCleanResultCard.isResultState(smartCareViewModel.state) {
                QuickCleanResultCard(state: smartCareViewModel.state,
                                     onDismiss: { smartCareViewModel.reset() })
            }
            // M3（P2 final）：推荐集为空时的诚实空态 —— 不再弹一张确认键
            // 禁用的空预演 sheet。指向画布上仍可手动预演的组。
            if smartCareViewModel.showsEmptyRecommendation {
                Text("canvas.quickclean.empty")
                    .font(AppFont.callout)
                    .foregroundStyle(Color.textSecondary)
            }
            HStack(spacing: AppSpacing.sm) {
                // 回收入口（P2 T5 R-统一）：触发快捷回收管线，`.confirming`
                // 落地后由根部预演 sheet 接管 —— 本页本身零清理动作。
                // fix r1（Critical 1）：container-only 时不渲染快捷回收按钮
                // （扫描一无所获的管线不该启动），改渲染授权卡。
                if QuickCleanGate.showsGrantCard(appScope.capability.level) {
                    if grantCardDismissed {
                        QuickCleanGrantDeclinedRow(onGrant: { grantCardDismissed = false })
                    } else {
                        QuickCleanGrantCard(
                            onGrant: { Task { await appScope.grant() } },
                            onSkip: { grantCardDismissed = true })
                    }
                }
                if !QuickCleanGate.showsGrantCard(appScope.capability.level) {
                    Button(action: onQuickClean) {
                        Text(quickCleanTitle)
                    }
                    .buttonStyle(.borderedProminent)
                }
                // 「+」菜单（P2 T4）：粉碎窗 · 归因规则（旧版空间地图项
                // 随 P2 T9 退役）。
                CanvasPlusMenu(actions: CanvasPlusMenuActions(
                    onShredder: onOpenShredder,
                    onAttributionRules: {
                        // corpus 未加载成功时不弹空 sheet（诚实降级——规则
                        // 链接行同样以 corpus 存在为渲染条件）。
                        if rulesCorpus != nil { showRulesSheet = true }
                    }))
                Button {
                    viewModel.startScan()
                } label: {
                    Text("canvas.hero.rescan")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, AppSpacing.xs)
        // fix r1（Important 2）：结果态 8 秒后自动复位回 idle（用户点
        // 「好」可立即复位；离开页面则 task 取消，状态保留到回来再展示）。
        .task(id: smartCareViewModel.state) {
            guard QuickCleanResultCard.isResultState(smartCareViewModel.state) else { return }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            smartCareViewModel.reset()
        }
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
            // fix r1 ②：只在扇出扫描中显示「取消」——引擎镜像态（扫描页发起）
            // 取消按钮对引擎扫描无效，显示即误导（点了闪回）。
            // fix r1（Important 1）：取消同时作废快捷回收管线（onScanCancelled
            // → RootView 重置 smartCareViewModel）—— 取消必须真的取消。
            if viewModel.showsScanCancel {
                Button {
                    viewModel.cancelScan()
                    onScanCancelled()
                } label: {
                    Text("canvas.scan.cancel")
                }
                .buttonStyle(.bordered)
            }
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
                // id 唯一性由 displayGroups 的同 kind 去重保证（fix r1 ②：
                // 扫描中旧报告组与增量组并存时，增量组替换同 kind 旧组）。
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    // 默认展开前 2 组（spec §3.4）；全量条目走 T6 下钻页。
                    CanvasGroupCard(group: group,
                                    initiallyExpanded: index < 2,
                                    onRehearse: onGroupAction)
                    // 组卡点击区 → 下钻页（T6，spec §6）：整卡点击打开，但
                    // 组头「就地清理」与展开箭头是独立 Button —— 自吃点击、
                    // 不触发导航（按钮优先级高于外层 tap 手势）。
                        .contentShape(Rectangle())
                        .onTapGesture { openDrillDown(group) }
                }
                .opacity(viewModel.scanPhase.isScanning ? 0.4 : 1)
                .disabled(viewModel.scanPhase.isScanning)
            }
        }
    }

    // MARK: - 下钻打开（T6，spec §6 数据切片）

    /// 组卡点击 → 计算下钻条目（cause 组从扫描树按 cause 切片，detection 组
    /// 直接用 CanvasEntry）→ 页面切换进下钻。切片在打开时刻算一次并随目的地
    /// 暂存，避免下钻期间每次 body 求值都重跑归因映射。
    private func openDrillDown(_ group: CanvasGroup) {
        let entries = GroupDrillDownSource.entries(
            for: group,
            categories: viewModel.categoriesProvider?() ?? [],
            engine: viewModel.attributionEngine)
        drillDown = DrillDownDestination(group: group, entries: entries)
    }

    // MARK: - 系统状态条（spec §3.5；P2 为静态占位，P3 改为真实 scope 状态行
    // —— MAS 授权态在此可见，直营版渲染静态全访问行，不再有占位假文案）

    @ViewBuilder
    private var systemStatusSection: some View {
        let level = appScope.capability.level
        Section {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: level == .containerOnly ? "lock" : "checkmark.seal")
                    .foregroundStyle(level == .containerOnly ? Color.warning : Color.success)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    switch level {
                    case .fullAccess:
                        Text("完整磁盘访问")
                            .font(AppFont.callout)
                            .foregroundStyle(Color.textPrimary)
                        Text("直营版可直接扫描完整磁盘。")
                            .font(AppFont.caption)
                            .foregroundStyle(Color.textSecondary)
                    case .homeGranted:
                        Text("主目录已授权")
                            .font(AppFont.callout)
                            .foregroundStyle(Color.textPrimary)
                        Text("扫描范围覆盖你的主目录。")
                            .font(AppFont.caption)
                            .foregroundStyle(Color.textSecondary)
                    case .containerOnly:
                        Text("仅容器访问")
                            .font(AppFont.callout)
                            .foregroundStyle(Color.textPrimary)
                        Text("授权主目录后才能发现并清理大部分垃圾文件。")
                            .font(AppFont.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer()
                if level == .containerOnly {
                    Button("授权主目录") {
                        Task { await appScope.grant() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
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
                // M2（P2 final）：本 App 无 NavigationStack（导航全走
                // appState 切换），NavigationLink 在此是死 UI —— 改为 sheet
                // 呈现（与「+」菜单 rules 项同一落点、同一份 corpus）。
                Button {
                    showRulesSheet = true
                } label: {
                    HStack {
                        Text("attr.rules.title")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(AppFont.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .buttonStyle(.plain)
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
