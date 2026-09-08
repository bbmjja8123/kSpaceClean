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
    // C3: this is now the *only* scan model the root owns. The legacy
    // `ScanViewModel` used to be wired to the toolbar button and the
    // ⌘N / ⌘R shortcuts while the rendered `ScanResultsView` observed this
    // model, so every user-initiated scan ran a pipeline nothing on screen
    // was watching. All three triggers now route here.
    @StateObject private var scanResultsViewModel = ScanResultsViewModel(
        engine: ScanEngine(orchestrator: ScanOrchestrator(scope: AppScope.shared.scope))
    )
    // v1.5: Smart Care (Phase B) — orchestrator + SwiftUI VM owns the
    // 3-step state machine. Attach lazily once `scanResultsViewModel`
    // is reachable (see `.onAppear` below).
    @StateObject private var smartCareViewModel = SmartCareViewModel()
    /// Live disk-health grade shown on the home grid card (v2.0 Phase 3).
    @StateObject private var diskHealthViewModel = DiskHealthViewModel()
    /// 空间地图 (v2.0 Phase 4) — renders the same tree the results view owns.
    @StateObject private var spaceMapViewModel = SpaceMapViewModel(
        rootsProvider: { [] }
    )
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

                    // Main content area (switches based on navigation)
                    mainContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

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
        // v1.5 stage B — see `docs/superpowers/plans/2026-08-09-kwise-v1.5-plan.md`.
        // Real module views land in Phase B Task 3+ / Phase C Task 7+ / Phase D Task 11+.
        case .smartCare:
            SmartCareHeroView(
                viewModel: smartCareViewModel,
                diskHealthViewModel: diskHealthViewModel
            )
        case .privacy:
            PrivacyView()  // Phase C Task 7 — wire PrivacyView into nav
        case .diskHealth:
            DiskHealthDetailView()  // Phase D Task 12 — wire disk health detail view
        case .startupItems:
            StartupItemsView()
        case .appUninstall:
            AppUninstallView(viewModel: makeAppUninstallViewModel())
        case .shredder:
            ShredderView()
        // v2.0 — toolbox + deep surfaces.
        case .tools:
            ToolboxView()
        case .spaceMap:
            SpaceMapView(viewModel: spaceMapViewModel)
        case .monthlyReport:
            MonthlyReportView()
        case .assistant:
            AssistantView()
        case .duplicates:
            DuplicateView(viewModel: makeDuplicateViewModel())
        case .largeOld:
            LargeOldView(viewModel: makeLargeOldViewModel())
        case .photoClean:
            PhotoCleanView(viewModel: makePhotoCleanViewModel())
        case .maintenance:
            MaintenanceView(viewModel: makeMaintenanceViewModel())
        }
    }

    // MARK: - Tool view-model factories

    /// Tool VMs get the graph engine (quota + sinks) and route quota
    /// exhaustion to the paywall. `@StateObject` keeps the first instance,
    /// so re-rendering does not recreate scanners.
    private func makeAppUninstallViewModel() -> AppUninstallViewModel {
        let vm = AppUninstallViewModel(engine: graph.cleanupEngine)
        vm.onQuotaExhausted = { coordinator.presentPaywall() }
        return vm
    }

    private func makeDuplicateViewModel() -> DuplicateViewModel {
        let vm = DuplicateViewModel(engine: graph.cleanupEngine)
        vm.onQuotaExhausted = { coordinator.presentPaywall() }
        return vm
    }

    private func makeLargeOldViewModel() -> LargeOldViewModel {
        let vm = LargeOldViewModel(engine: graph.cleanupEngine)
        vm.onQuotaExhausted = { coordinator.presentPaywall() }
        return vm
    }

    private func makePhotoCleanViewModel() -> PhotoCleanViewModel {
        let vm = PhotoCleanViewModel(engine: graph.cleanupEngine)
        vm.onQuotaExhausted = { coordinator.presentPaywall() }
        return vm
    }

    private func makeMaintenanceViewModel() -> MaintenanceViewModel {
        let vm = MaintenanceViewModel(engine: graph.cleanupEngine)
        vm.onQuotaExhausted = { coordinator.presentPaywall() }
        return vm
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
