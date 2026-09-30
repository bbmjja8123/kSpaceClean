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
    /// 页内零清理动作，唯一回收入口是「安全快捷回收」按钮（跳 Smart Care）。
    @StateObject private var anatomyViewModel = AnatomyViewModel(
        service: .live()
    )
    /// 磁盘健康（P1 T9 — T6 遗留条件）：DiskHealthCard 的新渲染位在解剖页，
    /// VM 与卡片在此持有、点击进入 `.diskHealth` 详情页。
    @StateObject private var diskHealthViewModel = DiskHealthViewModel()
    /// First-launch onboarding (v2.0 Phase 8) — welcome → PowerScope grant
    /// → menu bar & widget tour. Never re-shown once completed.
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
                    }
                }
        )
        .onAppear {
            // Late-bind the Smart Care VM to the scan VM. Two @StateObject
            // can't reference each other at init time; `.attach` resolves the
            // dependency once both views have been created.
            smartCareViewModel.attach(scanResultsViewModel: scanResultsViewModel)
            // v2.0 Phase 1 — DI unification: re-point both view models at the
            // graph engine so quota + event sinks apply to every cleanup
            // surface, and route quota exhaustion to the paywall sheet.
            cleanupViewModel.useEngine(graph.cleanupEngine)
            cleanupViewModel.onQuotaExhausted = { coordinator.presentPaywall() }
            smartCareViewModel.useEngine(graph.cleanupEngine)
            smartCareViewModel.onQuotaExhausted = { coordinator.presentPaywall() }
            // 空间地图 renders the scan tree — rebind the roots provider now
            // that scanResultsViewModel exists (init-time capture would be nil).
            spaceMapViewModel.rebindRoots { scanResultsViewModel.categories }
            // 空间解剖 reads the same live scan results（init-time capture 不可用，
            // 同 rebindRoots 的晚绑定模式）。
            anatomyViewModel.rebindCategories { scanResultsViewModel.categories }
            // P1 T4 — 清理预演的归因晚绑定：预演 sheet 逐项「为什么可以回收」
            // 读这份 report（T5 起数据源是解剖视图的 anatomy VM）。
            cleanupViewModel.attributionLookup = {
                anatomyViewModel.report?.items ?? []
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
            // First-launch onboarding (v2.0 Phase 8).
            if !onboardingCompleted {
                showOnboarding = true
            }
        }
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
        // P1 T5 — 解剖视图首屏（spec §1.1 英雄）:「你的 N GB，去哪了」。
        // 页内零清理动作；「安全快捷回收」是唯一回收入口，跳 Smart Care 次级页。
        case .anatomy:
            AnatomyView(
                viewModel: anatomyViewModel,
                diskHealthViewModel: diskHealthViewModel,
                onQuickClean: {
                    appState.navigation = .smartCare
                },
                onOpenDiskHealth: {
                    appState.navigation = .diskHealth
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
        case .monthlyReport:
            MonthlyReportView()
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
