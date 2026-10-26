import SwiftUI
import DesignSystem

/// RootView with navigation content switching.
/// Displays different content based on appState.navigation.
///
/// P2 T9（spec §2 单一主画布）：导航面收敛为 3 —— 解剖画布（首屏，含下钻
/// 路由）/ 历史 / 设置。粉碎窗与磁盘健康详情以 sheet 呈现，不再占据导航。
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
    // triggers (hero「重新扫描」, ⌘N / ⌘R, menu-bar quick scan) route
    // here so every user-initiated scan runs a pipeline the canvas is
    // actually watching. (P1 T9: the legacy rule-driven engine was
    // retired — the AppIntents now share this same orchestrator chain.)
    @StateObject private var scanResultsViewModel = ScanResultsViewModel(
        engine: ScanEngine(orchestrator: ScanOrchestrator(scope: AppScope.shared.scope))
    )
    // v1.5: Smart Care (Phase B) — orchestrator + SwiftUI VM owns the
    // 3-step state machine. Attach lazily once `scanResultsViewModel`
    // is reachable (see `.onAppear` below).
    @StateObject private var smartCareViewModel = SmartCareViewModel()
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
    /// VM 与卡片在此持有，点击打开详情 sheet（P2 T9：`.diskHealth` 导航面
    /// 退役，详情改走画布 sheet）。
    @StateObject private var diskHealthViewModel = DiskHealthViewModel()
    /// 整窗拖放粉碎（P2 T4）：拖拽悬停点亮「松开以粉碎」覆盖层，松开后
    /// 全为普通文件才转发粉碎窗（graph.shredderVM() 预填 + sheet 打开）。
    @StateObject private var dragToShred = DragToShredModel()
    /// 粉碎窗 sheet（「+」菜单 / 整窗拖放共用入口；VM 走 graph 缓存装配）。
    @State private var showShredWindow = false
    /// 应用卸载 sheet（P3 M5 重接入；graph.appUninstallVM 缓存装配）。
    @State private var showUninstallWindow = false
    /// 启动项 sheet（P3 M2 重接入；graph.startupItemsVM 缓存装配）。
    @State private var showStartupItemsWindow = false
    /// 磁盘健康详情 sheet（P2 T9：DiskHealthDetailView 保留为画布下钻页）。
    @State private var showDiskHealthDetail = false
    /// 统一预演 sheet（P2 T5 R-统一）：组头就地清理与 hero 快捷回收两条
    /// 入口的预演呈现节点（下钻入口的 sheet 同在此呈现 —— 三入口同一张
    /// ``CleanupRehearsalSheet``、同一条 CleanupViewModel 预演链：
    /// makeRehearsal → 确认 → executeConfirmedCleanup）。
    @State private var rehearsalPayload: RehearsalSheetPayload?
    /// hero 快捷回收的流程阶段 —— 决定 sheet 确认后是否给 orchestrator
    /// 回填 doneHero/failedHero，以及取消时是否复位状态机。
    /// ⚠️ 状态迁移不对称（fix r1 ⑥ 显式化）：`.running` 只由**画布 hero**
    /// 的 `onQuickClean` 置位；`.awaitingConfirm` 由共享的
    /// `.onReceive(smartCareViewModel.$state)` 对**所有触发源**（画布 hero /
    /// 菜单栏 quickClean）统一置位 —— 因为 `.confirming` 一律由根部预演
    /// sheet 接管。`.executing` 与 `.none` 只在 `finishRehearsal` / sheet
    /// 取消里迁移。
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
                    // Icon Rail (left sidebar) — brand mark on top, 3 items.
                    iconRail
                        .frame(width: 56)
                        .padding(.leading, 8)
                        .padding(.vertical, 12)

                    // Main content area (switches based on navigation)
                    mainContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 1024, minHeight: 680)
        // 整窗拖放粉碎（P2 T4）：挂在根内容上（rail / 画布都算有效投放区），
        // 覆盖层只在拖拽悬停期间出现——破坏性 UI 仅在表达意图后现身。
        // 接受的批次预填粉碎 VM 并打开粉碎窗；粉碎自身的 DELETE 确认链在
        // ShredderView 内，未被绕过。
        .modifier(DragToShredOverlay(model: dragToShred))
        // Task 5（feature sprint）：Dock 图标拖放 —— AppDelegate 的 open 事件
        // 经 `.klarisOpenFiles` 单向路由到同一 DragToShredModel（全有全无校验、
        // onShredRequested → 粉碎窗 sheet，与整窗拖放完全同一条链）。
        .onReceive(NotificationCenter.default.publisher(for: .klarisOpenFiles)) { note in
            guard let urls = note.userInfo?["urls"] as? [URL] else { return }
            _ = dragToShred.urlsDropped(urls)
        }
        .scanKeyboardShortcuts(
            onNewScan: {
                // ⌘N — switch to the canvas and start a fresh scan.
                // C1（P2 final）：所有扫描入口收敛到画布唯一入口 —— 先引擎
                // 扫描、后对新鲜树扇出，画布不再吃空树哑火。
                appState.navigation = .anatomy
                anatomyViewModel.startScan()
            },
            onRescan: {
                // ⌘R — 同一入口（画布管线自身区分首扫/重扫；.stopping 过渡
                // 期的重扫会被排队而非静默丢弃，I3）。
                appState.navigation = .anatomy
                anatomyViewModel.startScan()
            }
        )
        // Task 4（feature sprint）：⌘1/2/3 切 rail 三面；⌘, 打开设置
        // （app 无 Settings scene，约定键位绑定 rail 面而非静默失效）。
        .railKeyboardShortcuts(
            onAnatomy: { appState.navigation = .anatomy },
            onHistory: { appState.navigation = .history },
            onSettings: { appState.navigation = .settings }
        )
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
        // onboarding / 磁盘健康详情互斥共存。
        .background(
            Color.clear
                .sheet(isPresented: $showShredWindow) {
                    ShredderView(viewModel: graph.shredderVM())
                        .frame(minWidth: 560, minHeight: 420)
                }
        )
        // 应用卸载 sheet（P3 M5 重接入）——graph 缓存 VM；确认与提交语义
        // 在 AppUninstallView 内（引擎统一链，30 天可还原）。
        .background(
            Color.clear
                .sheet(isPresented: $showUninstallWindow) {
                    AppUninstallView(viewModel: graph.appUninstallVM {
                        coordinator.presentPaywall()
                    })
                    .frame(minWidth: 760, minHeight: 520)
                }
        )
        // 启动项 sheet（P3 M2 重接入）。
        .background(
            Color.clear
                .sheet(isPresented: $showStartupItemsWindow) {
                    StartupItemsView(viewModel: graph.startupItemsVM())
                        .frame(minWidth: 560, minHeight: 460)
                }
        )
        // 磁盘健康详情 sheet（P2 T9）——DiskHealthDetailView 保留为画布下钻
        // 深链页（spec §2：不占导航面，从 DiskHealthCard 点击进入）。
        .background(
            Color.clear
                .sheet(isPresented: $showDiskHealthDetail) {
                    // P3：注入画布 DiskHealthCard 的同一 VM（状态共享，详情
                    // 不再独立重拉）。
                    DiskHealthDetailView(viewModel: diskHealthViewModel)
                        .frame(minWidth: 560, minHeight: 420)
                }
        )
        // 统一预演 sheet（P2 T5）——独立 background 节点；组头/快捷回收/
        // 下钻三条入口在此呈现，确认只执行 sheet 上勾选的子集。
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
        //（覆盖 hero 快捷回收与菜单栏 quickClean 两个触发源）；扫描失败则
        // 复位状态机（快捷回收独立失败页已随 P2 T9 退役）。
        .onReceive(smartCareViewModel.$state) { state in
            switch state {
            case .confirming:
                quickCleanStage = .awaitingConfirm
                presentQuickCleanRehearsal()
            case .failed:
                if quickCleanStage == .running {
                    // fix r1（Important 2）：失败不再立即复位吞掉 —— hero
                    // 的结果卡展示失败信息，8 秒自动复位（或点「好」）。
                    quickCleanStage = .none
                }
            default:
                break
            }
        }
        // Task 2 完成时刻：任一统一链清理成功 → 完成音效（用户可关，
        // settings.sound.completion）。lastOutcome 由统一链
        // executeConfirmedCleanup 写入 —— 组头就地清理 / hero 快捷回收 /
        // 下钻「预演并清理」三个入口都在这条链上，一处 onReceive 全覆盖。
        // brief 原稿读 outcome.successCount —— CleanupOutcome 无该字段，
        // 等价改为「有成功 URL」（succeeded 非空）。
        .onReceive(cleanupViewModel.$lastOutcome) { outcome in
            guard let outcome, !outcome.succeeded.isEmpty else { return }
            CompletionSound.playIfEnabled(UserPreferences.load().playCompletionSound)
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
            // P2 final residual（re-review）：设置页隐私清理并入 graph 引擎
            // —— 同一条统一链的 CleanupViewModel 连 graph.cleanupEngine
            // （quota 买断门 + 事件 sink），配额超限同样路由买断墙。graph
            // 缓存保证设置页取到这一同一实例（privacyCleanupVM 工厂）。
            graph.privacyCleanupVM { coordinator.presentPaywall() }
            // 空间解剖 reads the live scan results（init-time capture 不可用，
            // rebindRoots 的晚绑定模式）。
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
            // P2 T9：扫描与快捷回收都落在解剖画布（独立扫描/Smart Care 页
            // 已退役）。
            graph.menuBarManager.onQuickScan = {
                NSApp.activate(ignoringOtherApps: true)
                appState.navigation = .anatomy
                // C1（P2 final）：菜单栏扫描同样收敛到画布唯一入口。
                anatomyViewModel.startScan()
            }
            graph.menuBarManager.onQuickClean = {
                NSApp.activate(ignoringOtherApps: true)
                appState.navigation = .anatomy
                // fix r1（Critical 1）：container-only 门控同样适用于菜单栏
                // 入口 —— 未授权不启动管线（hero 上有授权卡承接）。
                guard QuickCleanGate.allowsPipeline(AppScope.shared.capability.level) else { return }
                quickCleanStage = .running
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

    // MARK: - Main Content（P2 T9：3 分支 + sheet 呈现的下钻面）
    @ViewBuilder
    private var mainContent: some View {
        switch appState.navigation {
        case .history:
            TimelineView()
        case .settings:
            SettingsView()
        // P1 T5 — 解剖视图首屏 → P2 T3 主画布（spec §3）:「你的 N GB，去哪了」。
        // P2 T5 R-统一：页内三条预演入口（组头就地清理 / hero 快捷回收 /
        // 下钻「预演并清理」）都经根部预演 sheet → 统一链执行。
        case .anatomy:
            AnatomyView(
                viewModel: anatomyViewModel,
                coordinator: canvasCoordinator,
                diskHealthViewModel: diskHealthViewModel,
                smartCareViewModel: smartCareViewModel,
                onQuickClean: {
                    // R-统一：快捷回收 = 推荐项预演。留在画布（扫描态由
                    // bindScanViewModel 镜像进 hero）；`.confirming` 一到，
                    // 根部 onReceive 弹推荐项预演 sheet。
                    // fix r1（Critical 1）：container-only 门控 —— 授权卡在
                    // hero 上（AnatomyView），管线不允许启动。
                    guard QuickCleanGate.allowsPipeline(AppScope.shared.capability.level) else { return }
                    quickCleanStage = .running
                    smartCareViewModel.runSmartCare()
                },
                onOpenDiskHealth: {
                    // P2 T9：详情不占导航面 —— 画布下钻以 sheet 呈现。
                    showDiskHealthDetail = true
                },
                onGroupAction: { group in
                    presentGroupRehearsal(group)
                },
                onOpenShredder: {
                    // 「+」菜单 → 粉碎窗（graph.shredderVM() 缓存装配复用）。
                    showShredWindow = true
                },
                onOpenUninstall: {
                    // P3 M5 重接入：「+」菜单 → 应用卸载 sheet（graph 缓存
                    // 装配 + 配额超限路由买断墙）。
                    _ = graph.appUninstallVM { coordinator.presentPaywall() }
                    showUninstallWindow = true
                },
                onOpenStartupItems: {
                    // P3 M2 重接入：「+」菜单 → 启动项 sheet（graph 缓存装配）。
                    _ = graph.startupItemsVM()
                    showStartupItemsWindow = true
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
                onDrillDownRehearse: { context, entries in
                    // P2 T6 — 下钻「预演并清理」：勾选集条目（target + 徽章）
                    // 直入同一条预演链，sheet 以组名为语境（与组头就地清理
                    // 同源；I1 徽章进预演 → 非绿徽默认豁免）。
                    presentDrillDownRehearsal(entries: entries, context: context)
                }
            )
        }
    }

    // MARK: - 统一预演（P2 T5 R-统一）

    /// 组头「就地清理」→ 组过滤预演：组内 `CanvasEntry.target` 直入预演链，
    /// sheet 以组名为语境。三入口统一句式的第一条（下钻入口的 sheet 同在
    /// 根部呈现，同一条 VM 链）。
    private func presentGroupRehearsal(_ group: CanvasGroup) {
        // I1（P2 final）：entries 直入预演 —— 徽章随条目进 sheet，
        // 「数据·不属垃圾」等非绿徽条目默认豁免（C4 违约修复）。
        let entries = group.entries.filter { $0.target != nil }
        // 组装器保证 rehearse 组的条目非空且带 target；防御性兜底而已。
        guard !entries.isEmpty else { return }
        Task {
            let items = await cleanupViewModel.makeRehearsal(entries: entries)
            rehearsalPayload = RehearsalSheetPayload(items: items, context: group.title)
        }
    }

    /// 下钻页「预演并清理」（P2 T6）→ 勾选集预演：勾选集**条目**直入
    /// `makeRehearsal(entries:)`（target 的 risk/bundleID/categoryID 与
    /// 五色徽章原样保留），sheet 以下钻组名为语境；确认执行复用统一链
    /// `executeConfirmedCleanup`。勾选集为空时按钮已禁用，此守卫纯防御。
    private func presentDrillDownRehearsal(entries: [CanvasEntry], context: String) {
        guard !entries.isEmpty else { return }
        Task {
            let items = await cleanupViewModel.makeRehearsal(entries: entries)
            rehearsalPayload = RehearsalSheetPayload(items: items, context: context)
        }
    }

    /// hero 快捷回收 → 推荐项预演（已勾选好）。C4：`recommendedTargets`
    /// 已由 `IntentScanAdapter` 的 `riskLevel.defaultChecked` 门控保证不含
    /// 危险项。M3（P2 final）：推荐集为空时不再弹可禁用的空 sheet ——
    /// 复位状态机并在 hero 呈现诚实空态文案。
    private func presentQuickCleanRehearsal() {
        let recommended = smartCareViewModel.recommendedTargets
        guard !recommended.isEmpty else {
            quickCleanStage = .none
            smartCareViewModel.markEmptyRecommendation()
            return
        }
        Task {
            let items = await cleanupViewModel.makeRehearsal(targets: recommended)
            rehearsalPayload = RehearsalSheetPayload(items: items)
        }
    }

    /// 预演确认 → 统一链执行（确认只执行 sheet 上勾选的子集）。快捷回收
    /// 路径再把结果回填给 orchestrator；组头路径执行完就地关闭 sheet 即可。
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
        // I2（P2 final）：就地清理成功 → 画布就地失效（移除已清理条目/组、
        // 作废下钻勾选缓存、重跑归因）—— 不等下一次重扫画布才反映新事实。
        if let outcome {
            await anatomyViewModel.applyCleanupOutcome(outcome)
        }
        guard quickClean else { return }
        quickCleanStage = .none
        if let outcome {
            smartCareViewModel.completeQuickClean(
                freedBytes: outcome.freedBytes,
                durationSeconds: Date().timeIntervalSince(started))
        } else {
            smartCareViewModel.failQuickClean(
                message: String(localized: String.LocalizationValue("canvas.quickclean.failedRetry")))
        }
        // P2 T9：Smart Care 页已退役 —— 快捷回收留在画布上完成（结果状态
        // 由 orchestrator 持有，下一次快捷回收重新计算）。
        appState.navigation = .anatomy
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
                // Fixed rail (P2 T1 收敛、T9 定稿): anatomy / history / settings.
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
        // A11y 审计：rail 按钮此前只有 .help（VoiceOver 不读）——补显式 label
        // + 选中特征，导航结构才进 VoiceOver 的 rotor。
        .accessibilityLabel(Text(item.tooltip))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // P3 UI 冒烟：rail 按钮标识（SmokeUITests 按 identifier 导航）。
        .accessibilityIdentifier("rail.\(item.rawValue)")
    }
}

