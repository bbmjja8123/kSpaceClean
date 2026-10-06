import SwiftUI
import DesignSystem

/// RootView with navigation content switching.
/// Displays different content based on appState.navigation.
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.appGraph) private var injectedGraph
    @StateObject private var cleanupViewModel = CleanupViewModel()

    /// The injected graph in production; a lazily-built standalone graph only
    /// in previews/tests that run without `kWiseApp`.
    private var graph: AppGraph { injectedGraph ?? AppGraph() }

    // C1: production scan pipeline. Owned at the root so the scan state
    // survives navigation switches (e.g. user starts a scan, navigates
    // away, comes back — the categories tree is still there).
    //
    // C3: this is now the *only* scan model the root owns. All scan
    // triggers (toolbar-era buttons, ⌘N / ⌘R, menu-bar quick scan) route
    // here so every user-initiated scan runs a pipeline the screen is
    // actually watching. (P1 T9: the legacy rule-driven engine was
    // retired — the AppIntents now share this same orchestrator chain.)
    @StateObject private var scanResultsViewModel = ScanResultsViewModel(
        engine: ScanEngine(orchestrator: ScanOrchestrator(scope: AppScope.shared.scope))
    )
    // v1.5: Smart Care (Phase B) — orchestrator + SwiftUI VM owns the
    // 3-step state machine. Attach lazily once `scanResultsViewModel`
    // is reachable (see `.onAppear` below).
    @StateObject private var smartCareViewModel = SmartCareViewModel()
    /// 空间地图 (v2.0 Phase 4) — renders the same tree the results view owns.
    @StateObject private var spaceMapViewModel = SpaceMapViewModel(
        rootsProvider: { [] }
    )
    /// 空间解剖（P1 T5 新首屏）— 与空间地图共用同一棵扫描树，服务只读不清理；
    /// 页内零清理动作，回收入口（组头就地清理 / hero 快捷回收）都经根部
    /// 统一预演 sheet（P2 T5 R-统一）。
    @StateObject private var anatomyViewModel = AnatomyViewModel(
        service: .live()
    )
    /// 主画布扇出协调器（P2 T3）— hero「重新扫描」的引擎（归因 → 重复 →
    /// 照片 → 大文件），增量组/诊断/虚线卡经 @Published 直接上画布。
    @StateObject private var canvasCoordinator = CanvasScanCoordinator()
    /// 磁盘健康（P1 T9 — T6 遗留条件）：DiskHealthCard 的新渲染位在解剖页，
    /// VM 与卡片在此持有、点击进入 `.diskHealth` 详情页。
    @StateObject private var diskHealthViewModel = DiskHealthViewModel()
    /// 整窗拖放粉碎（P2 T4）：拖拽悬停点亮「松开以粉碎」覆盖层，松开后
    /// 全为普通文件才转发粉碎窗（graph.shredderVM() 预填 + sheet 打开）。
    @StateObject private var dragToShred = DragToShredModel()
    /// 粉碎窗 sheet（「+」菜单 / 整窗拖放共用入口；VM 走 graph 缓存装配，
    /// 与 `.shredder` 页共享同一份暂存/历史状态）。
    @State private var showShredWindow = false
    /// 统一预演 sheet（P2 T5 R-统一）：组头就地清理与 hero 快捷回收两条
    /// 入口的预演呈现节点（下钻入口的 sheet 仍在 ScanResultsView 内 ——
    /// 三入口同一张 ``CleanupRehearsalSheet``、同一条 CleanupViewModel
    /// 预演链：makeRehearsal → 确认 → executeConfirmedCleanup）。
    @State private var rehearsalPayload: RehearsalSheetPayload?
    /// hero 快捷回收的流程阶段 —— 决定 sheet 确认后是否给 orchestrator
    /// 回填 doneHero/failedHero，以及取消时是否复位状态机。
    /// ⚠️ 状态迁移不对称（fix r1 ⑥ 显式化）：`.running` 只由**画布 hero**
    /// 的 `onQuickClean` 置位；`.awaitingConfirm` 由共享的
    /// `.onReceive(smartCareViewModel.$state)` 对**所有触发源**（画布 hero /
    /// smartCare 页 idle hero / 菜单栏 quickClean）统一置位 —— 因为
    /// `.confirming` 一律由根部预演 sheet 接管。`.executing` 与 `.none` 只
    /// 在 `finishRehearsal` / sheet 取消里迁移。
    @State private var quickCleanStage: QuickCleanStage = .none

    /// P2 T5 R-统一：快捷回收 = 推荐项预演（已勾选好）→ 确认 → 统一链执行。
    private enum QuickCleanStage: Equatable {
        /// hero/菜单栏触发的扫描 + 推荐计算进行中。
        case running
        /// `.confirming` 已落到预演 sheet，等待用户确认/取消。
        case awaitingConfirm
        /// sheet 已确认，统一链执行中。
        case executing
        case none
    }
    /// First-launch onboarding (v2.0 Phase 8; P2 T8 收敛为 3 页) — welcome →
    /// 扫描承诺+主目录授权合并页 → 完成即扫. Never re-shown once completed.
    @AppStorage("onboarding.completed.v1") private var onboardingCompleted = false
    @State private var showOnboarding = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Layer 1: Background
                backgroundLayer

                // UX 重构 (v2.1 Phase 1): the top toolbar is gone — its four
                // buttons all duplicated rail items. The rail is now the only
                // global navigation; page-level actions live inside each page.
                HStack(spacing: 0) {
                    // Icon Rail (left sidebar) — brand mark on top, fixed 6 items.
                    iconRail
                        .frame(width: 56)
                        .padding(.leading, 8)
                        .padding(.vertical, 12)

                    VStack(spacing: 0) {
                        // v2.5 Tab 化工具箱：有打开的 Tab 时顶部显示 Tab 行。
                        if !appState.toolTabs.isEmpty {
                            ToolTabBar(
                                tabs: appState.toolTabs,
                                activeToolTabID: appState.activeToolTabID,
                                isToolPageActive: appState.navigation.isToolboxTool,
                                onActivate: { appState.activateToolTab($0) },
                                onClose: { appState.closeToolTab($0) },
                                onToolbox: { appState.navigation = .tools }
                            )
                            Divider().background(Color.divider)
                        }

                        // Main content area (switches based on navigation)
                        mainContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    // Selection detail panel (UX 重构 Phase 3): auto-hidden
                    // until a row is tapped; ⌘I toggles. No compensating
                    // paddings — the rail/content alignment accounts for it.
                    if appState.rightPanelVisible, appState.detailSelection != nil {
                        DetailPanelView(viewModel: scanResultsViewModel)
                            .frame(width: min(280, geo.size.width * 0.28))
                            .padding(.trailing, 12)
                            .padding(.vertical, 12)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
        }
        .frame(minWidth: 1024, minHeight: 680)
        // 整窗拖放粉碎（P2 T4）：挂在根内容上（rail / Tab 行 / 画布都算
        // 有效投放区），覆盖层只在拖拽悬停期间出现——破坏性 UI 仅在表达
        // 意图后现身。接受的批次预填粉碎 VM 并打开粉碎窗；粉碎自身的
        // DELETE 确认链在 ShredderView 内，未被绕过。
        .modifier(DragToShredOverlay(model: dragToShred))
        .scanKeyboardShortcuts(
            onNewScan: {
                // ⌘N — switch to the scan surface and start a fresh scan
                appState.navigation = .scan
                scanResultsViewModel.startScan()
            },
            onRescan: {
                // ⌘R — re-run the scan using the same root paths and filters
                // (ScanResultsViewModel does not differentiate "new" from
                // "rescan"; both delegate to startScan(), which cancels any
                // in-flight orchestrator run before starting a new one.)
                appState.navigation = .scan
                scanResultsViewModel.startScan()
            }
        )
        .modifier(RootKeyboardShortcuts(appState: appState))
        // Free-tier paywall — the only place the sheet is presented from
        // (v2.0 Phase 1). `CleanupOutcome.quotaExhausted` routes here via
        // `AppCoordinator.presentPaywall()`.
        .sheet(item: $coordinator.presentedSheet) { _ in
            PaywallView(store: graph.storeManager)
        }
        // First-launch onboarding — attached to a nested view so it can
        // coexist with the paywall sheet (only one sheet per view node).
        .background(
            Color.clear
                .sheet(isPresented: $showOnboarding) {
                    OnboardingContainerView {
                        onboardingCompleted = true
                        showOnboarding = false
                        // P2 T8 — 完成即扫：Onboarding 收口后自动跑一次主画布
                        // 扫描（onAppear 已 bindCoordinator，startScan 守卫完备）。
                        // FirstScanGate 的 UserDefaults flag 钉住「恰一次」：
                        // onboarding 标记被重置的场景也不会二次自动扫描。
                        if FirstScanGate.shouldAutoScan() {
                            anatomyViewModel.startScan()
                        }
                    }
                }
        )
        // 粉碎窗 sheet（P2 T4）——同样挂独立 background 节点，与 paywall /
        // onboarding 两个 sheet 互斥共存。
        .background(
            Color.clear
                .sheet(isPresented: $showShredWindow) {
                    ShredderView(viewModel: graph.shredderVM())
                        .frame(minWidth: 560, minHeight: 420)
                }
        )
        // 统一预演 sheet（P2 T5）——独立 background 节点；组头/快捷回收
        // 两条新入口在此呈现，确认只执行 sheet 上勾选的子集。
        .background(
            Color.clear
                .sheet(item: $rehearsalPayload) { payload in
                    CleanupRehearsalSheet(
                        items: payload.items,
                        context: payload.context,
                        onConfirm: { confirmed in
                            let quickClean = quickCleanStage == .awaitingConfirm
                            rehearsalPayload = nil
                            Task {
                                await finishRehearsal(confirmed,
                                                      quickClean: quickClean)
                            }
                        },
                        onCancel: {
                            rehearsalPayload = nil
                            if quickCleanStage == .awaitingConfirm {
                                quickCleanStage = .none
                                smartCareViewModel.reset()
                            }
                        },
                        isExecuting: cleanupViewModel.isCleaning
                    )
                    .frame(width: 560, height: 480)
                }
        )
        // R-统一：Smart Care 落到 `.confirming` 时一律由预演 sheet 接管
        //（覆盖 hero 快捷回收、smartCare 页 idle hero 与菜单栏 quickClean
        // 三个触发源）；扫描失败则把 failedHero 展示给发起页。
        .onReceive(smartCareViewModel.$state) { state in
            switch state {
            case .confirming:
                quickCleanStage = .awaitingConfirm
                presentQuickCleanRehearsal()
            case .failed:
                if quickCleanStage == .running {
                    quickCleanStage = .none
                    appState.navigation = .smartCare
                }
            default:
                break
            }
        }
        .onAppear {
            // Late-bind the Smart Care VM to the scan VM. Two @StateObject
            // can't reference each other at init time; `.attach` resolves the
            // dependency once both views have been created.
            smartCareViewModel.attach(scanResultsViewModel: scanResultsViewModel)
            // v2.0 Phase 1 — DI unification: re-point the cleanup view model
            // at the graph engine so quota + event sinks apply to every
            // cleanup surface, and route quota exhaustion to the paywall
            // sheet. P2 T5（R-统一）：Smart Care 的执行也归这条链 ——
            // orchestrator 不再单独持有引擎。
            cleanupViewModel.useEngine(graph.cleanupEngine)
            cleanupViewModel.onQuotaExhausted = { coordinator.presentPaywall() }
            // 空间地图 renders the scan tree — rebind the roots provider now
            // that scanResultsViewModel exists (init-time capture would be nil).
            spaceMapViewModel.rebindRoots { scanResultsViewModel.categories }
            // 空间解剖 reads the same live scan results（init-time capture 不可用，
            // 同 rebindRoots 的晚绑定模式）。
            anatomyViewModel.rebindCategories { scanResultsViewModel.categories }
            // P2 T6 — 下钻页节点问答的数据源（AssistantNodePanel 复用组件）。
            anatomyViewModel.rebindScanResults { [weak scanResultsViewModel] in scanResultsViewModel }
            // P2 T3 — 主画布：扇出协调器注入 + 扫描页 VM 绑定（isScanning
            // true→false → 归因刷新，P1 修复波机制自下方 .onChange 迁入 VM）。
            anatomyViewModel.bindCoordinator(canvasCoordinator)
            anatomyViewModel.bindScanViewModel(scanResultsViewModel)
            // P1 T4 — 清理预演的归因晚绑定：预演 sheet 逐项「为什么可以回收」
            // 读这份 report（T5 起数据源是解剖视图的 anatomy VM）。
            // P1 final (F3a)：供 `allAttributions`（certain + refused/probable）
            // ——只供 `items` 时 sheet 的 probable 分支哑火、未访问解剖页就清理
            // 的用户拿不到任何归因。
            cleanupViewModel.attributionLookup = {
                anatomyViewModel.report?.allAttributions ?? []
            }
            // Menu bar quick actions (C-8, v2.0 Phase 3): route through the
            // coordinator — the menu never mutates appState directly.
            graph.menuBarManager.onQuickScan = {
                NSApp.activate(ignoringOtherApps: true)
                appState.navigation = .scan
                scanResultsViewModel.startScan()
            }
            graph.menuBarManager.onQuickClean = {
                NSApp.activate(ignoringOtherApps: true)
                appState.navigation = .smartCare
                smartCareViewModel.runSmartCare()
            }
            graph.menuBarManager.onOpenSettings = {
                appState.navigation = .settings
            }
            // P2 T4 — 整窗拖放粉碎的转发目标：全为普通文件（DragToShredModel
            // 校验）才预填 graph.shredderVM() 并打开粉碎窗；确认链仍在
            // ShredderView 的 DELETE 流程内，这里只做「开窗 + 预填」。
            dragToShred.onShredRequested = { urls in
                graph.shredderVM().performDrop(urls: urls)
                showShredWindow = true
            }
            // First-launch onboarding (v2.0 Phase 8).
            if !onboardingCompleted {
                showOnboarding = true
            }
        }
        // P1 final (F3b)：扫描结束即重跑归因 —— 该机制自 P2 T3 起由
        // anatomyViewModel.bindScanViewModel 的 Combine 订阅承担（isScanning
        // true→false → refresh），RootView 不再挂 .onChange。
    }

    // MARK: - Background
    @ViewBuilder
    private var backgroundLayer: some View {
        Color.bgPrimary.ignoresSafeArea()
    }

    // MARK: - Main Content
    @ViewBuilder
    private var mainContent: some View {
        switch appState.navigation {
        case .scan:
            ScanResultsView(
                viewModel: scanResultsViewModel,
                smartCareViewModel: smartCareViewModel,
                cleanupViewModel: cleanupViewModel
            )
        case .cleanup:
            CleanupContentView(viewModel: cleanupViewModel)
        case .history:
            TimelineView()
        case .settings:
            SettingsView()
        // P1 T5 — 解剖视图首屏 → P2 T3 主画布（spec §3）:「你的 N GB，去哪了」。
        // P2 T5 R-统一：页内两条预演入口（组头就地清理 / hero 快捷回收）
        // 都经根部预演 sheet → 统一链执行 —— 本页仍零直接清理动作。
        case .anatomy:
            AnatomyView(
                viewModel: anatomyViewModel,
                coordinator: canvasCoordinator,
                diskHealthViewModel: diskHealthViewModel,
                onQuickClean: {
                    // R-统一：快捷回收 = 推荐项预演。留在画布（扫描态由
                    // bindScanViewModel 镜像进 hero）；`.confirming` 一到，
                    // 根部 onReceive 弹推荐项预演 sheet。
                    quickCleanStage = .running
                    smartCareViewModel.runSmartCare()
                },
                onOpenDiskHealth: {
                    appState.navigation = .diskHealth
                },
                onGroupAction: { group in
                    presentGroupRehearsal(group)
                },
                onOpenShredder: {
                    // 「+」菜单 → 粉碎窗（graph.shredderVM() 缓存装配复用，
                    // 与 `.shredder` 页共享暂存状态）。
                    showShredWindow = true
                },
                onSpaceMapLegacy: {
                    // 「+」菜单 → 旧版空间地图（W4 退役前的逃生口）。
                    appState.navigation = .spaceMap
                },
                onScanCancelled: {
                    // fix r1（Important 1）：取消必须真的取消 —— 扇出取消
                    // 之外，快捷回收管线（runSmartCare → 引擎扫描 → 推荐计算）
                    // 也要一并作废；否则取消后管线照样落 `.confirming`，
                    // 模态预演 sheet 会在用户明确取消后弹出。
                    if quickCleanStage == .running {
                        quickCleanStage = .none
                        smartCareViewModel.reset()
                    }
                },
                onDrillDownRehearse: { context, targets in
                    // P2 T6 — 下钻「预演并清理」：勾选集 targets 直入同一条
                    // 预演链，sheet 以组名为语境（与组头就地清理同源）。
                    presentDrillDownRehearsal(targets: targets, context: context)
                }
            )
        // P1 T6 — smartCare 降级为「安全快捷回收」次级页（spec §3.1）：
        // 单卡状态机 + 诚实说明行；不再充当导航枢纽。
        case .smartCare:
            SmartCareHeroView(viewModel: smartCareViewModel)
        case .privacy:
            PrivacyView()  // Phase C Task 7 — wire PrivacyView into nav
        case .diskHealth:
            DiskHealthDetailView()  // Phase D Task 12 — wire disk health detail view
        case .startupItems:
            StartupItemsView(viewModel: graph.startupItemsVM())
        case .appUninstall:
            AppUninstallView(viewModel: makeAppUninstallViewModel())
        case .shredder:
            ShredderView(viewModel: graph.shredderVM())
        // v2.0 — toolbox + deep surfaces.
        case .tools:
            ToolboxView()
        case .spaceMap:
            SpaceMapView(viewModel: spaceMapViewModel)
        case .duplicates:
            DuplicateView(viewModel: makeDuplicateViewModel())
        case .largeOld:
            LargeOldView(viewModel: makeLargeOldViewModel())
        case .photoClean:
            PhotoCleanView(
                viewModel: makePhotoCleanViewModel(),
                similarityViewModel: makePhotoSimilarityViewModel()
            )
        case .maintenance:
            MaintenanceView(viewModel: makeMaintenanceViewModel())
        // P1 T5/T8：`.attribution` 验证面与 `.assistant` 聊天框均已退役 ——
        // 枚举 case 已删，工具箱卡片直达 `.anatomy`，问答内嵌 DetailPanel。
        }
    }

    // MARK: - 统一预演（P2 T5 R-统一）

    /// 组头「就地清理」→ 组过滤预演：组内 `CanvasEntry.target` 直入预演链，
    /// sheet 以组名为语境。三入口统一句式的第一条（下钻入口的 sheet 在
    /// ScanResultsView 内，同一条 VM 链）。
    private func presentGroupRehearsal(_ group: CanvasGroup) {
        let targets = group.entries.compactMap(\.target)
        // 组装器保证 rehearse 组的条目非空且带 target；防御性兜底而已。
        guard !targets.isEmpty else { return }
        Task {
            let items = await cleanupViewModel.makeRehearsal(targets: targets)
            rehearsalPayload = RehearsalSheetPayload(items: items, context: group.title)
        }
    }

    /// 下钻页「预演并清理」（P2 T6）→ 勾选集预演：勾选集 targets 直入
    /// `makeRehearsal(targets:)`（risk/bundleID/categoryID 原样保留），sheet
    /// 以下钻组名为语境；确认执行复用统一链 `executeConfirmedCleanup`。
    /// 勾选集为空时按钮已禁用，此守卫纯防御。
    private func presentDrillDownRehearsal(targets: [CleanupTarget], context: String) {
        guard !targets.isEmpty else { return }
        Task {
            let items = await cleanupViewModel.makeRehearsal(targets: targets)
            rehearsalPayload = RehearsalSheetPayload(items: items, context: context)
        }
    }

    /// hero 快捷回收 → 推荐项预演（已勾选好）。C4：`recommendedTargets`
    /// 已由 `IntentScanAdapter` 的 `riskLevel.defaultChecked` 门控保证不含
    /// 危险项。
    private func presentQuickCleanRehearsal() {
        Task {
            let items = await cleanupViewModel.makeRehearsal(
                targets: smartCareViewModel.recommendedTargets)
            rehearsalPayload = RehearsalSheetPayload(items: items)
        }
    }

    /// 预演确认 → 统一链执行（确认只执行 sheet 上勾选的子集）。快捷回收
    /// 路径再把结果回填给 orchestrator（doneHero / failedHero）并导航到
    /// smartCare 页展示；组头路径执行完就地关闭 sheet 即可。
    private func finishRehearsal(_ confirmed: [CleanupTarget],
                                 quickClean: Bool) async {
        // sheet 在 confirmedItems 为空时禁用确认；此守卫纯防御。
        guard !confirmed.isEmpty else {
            if quickClean {
                quickCleanStage = .none
                smartCareViewModel.reset()
            }
            return
        }
        let started = Date()
        if quickClean {
            quickCleanStage = .executing
            smartCareViewModel.beginQuickCleanExecution()
        }
        // fix r1（Important 2）：成败以**本次运行的返回值**判定 —— 返回值
        // 为 nil（引擎抛错 / no-op）即走 failExecution，绝不读 `lastOutcome`
        // 推断（上次成功的旧字节不能顶替本次失败展示成 doneHero）。
        let outcome = await cleanupViewModel.executeConfirmedCleanup(
            sizes: nil, confirmedTargets: confirmed)
        guard quickClean else { return }
        quickCleanStage = .none
        if let outcome {
            smartCareViewModel.completeQuickClean(
                freedBytes: outcome.freedBytes,
                durationSeconds: Date().timeIntervalSince(started))
        } else {
            smartCareViewModel.failQuickClean(message: "清理未能完成，请重试")
        }
        appState.navigation = .smartCare
    }

    // MARK: - Tool view-model factories

    /// v2.5 Tab 化工具箱：VM 全部缓存在 AppGraph（每个工具一份常驻），
    /// Tab 切换只换视图，工具内部状态（扫描结果/已选/进度）永不丢失。
    private func makeAppUninstallViewModel() -> AppUninstallViewModel {
        graph.appUninstallVM { coordinator.presentPaywall() }
    }

    private func makeDuplicateViewModel() -> DuplicateViewModel {
        graph.duplicatesVM { coordinator.presentPaywall() }
    }

    private func makeLargeOldViewModel() -> LargeOldViewModel {
        graph.largeOldVM { coordinator.presentPaywall() }
    }

    private func makePhotoCleanViewModel() -> PhotoCleanViewModel {
        graph.photoCleanVM { coordinator.presentPaywall() }
    }

    private func makePhotoSimilarityViewModel() -> PhotoSimilarityViewModel {
        graph.photoSimilarityVM { coordinator.presentPaywall() }
    }

    private func makeMaintenanceViewModel() -> MaintenanceViewModel {
        graph.maintenanceVM { coordinator.presentPaywall() }
    }

    // MARK: - Icon Rail
    private var iconRail: some View {
        GlassPanel {
            VStack(spacing: 4) {
                // Brand mark — the toolbar's only unique asset, preserved
                // here at the top of the rail.
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.brandPrimary)
                    .frame(width: 36, height: 36)
                    .help("kWise")
                Divider()
                    .padding(.horizontal, AppSpacing.sm)
                // Fixed rail (v2.0 Phase 2): deep surfaces live in the
                // toolbox instead of growing the rail.
                ForEach(AppState.NavigationItem.railItems, id: \.self) { item in
                    IconRailButton(
                        item: item,
                        isSelected: appState.navigation == item,
                        action: { appState.navigation = item }
                    )
                }
                Spacer()
            }
            .padding(.vertical, AppSpacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// F9 perf sweep: small Equatable helper view that wraps each icon
/// rail button. `.equatable()` on it means a `navigation` change
/// only re-evaluates the two affected buttons (selected and
/// deselected) instead of every button in the rail. Equality is
/// `(item, isSelected)` because the row body depends only on those.
private struct IconRailButton: View, Equatable {
    let item: AppState.NavigationItem
    let isSelected: Bool
    let action: () -> Void

    static func == (lhs: IconRailButton, rhs: IconRailButton) -> Bool {
        lhs.item == rhs.item && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: item.iconName)
                .font(.system(size: 16))
                .frame(width: 36, height: 36)
                .background(isSelected ? Color.brandPrimary.opacity(0.3) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        }
        .buttonStyle(.plain)
        .help(item.tooltip)
    }
}

// MARK: - Root Keyboard Shortcuts

/// Global keyboard shortcuts for the main app window.
private struct RootKeyboardShortcuts: ViewModifier {
    @ObservedObject var appState: AppState
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    let isCommand = flags == .command

                    guard isCommand else { return event }

                    switch event.charactersIgnoringModifiers {
                    case "i":
                        // ⌘I — toggle the selection detail panel (macOS
                        // inspector convention, UX 重构 Phase 1).
                        appState.rightPanelVisible.toggle()
                        return nil
                    default: return event
                    }
                }
            }
            .onDisappear {
                if let monitor = monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
            }
    }
}
