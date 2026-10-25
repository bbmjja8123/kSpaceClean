import SwiftUI
import PowerScope
import CommonUtils
import FileScanner
import DesignSystem

/// The application's dependency graph — Phase 2's single DI root.
///
/// One `AppGraph` is built in `kWiseApp` and injected via
/// `.environment(\.appGraph, …)`. Child view models stop newsing up their
/// own engines: the previous state (two `StoreManager` instances, ad-hoc
/// `CleanupEngine()` per view, `CoreDataStack.shared` reached from scan
/// code) made subscription state and cleanup history unshareable.
///
/// `AppGraph.shared` exists for out-of-process surfaces (App Intents, widget
/// intents) that must construct the same service graph without the UI layer.
@MainActor
public final class AppGraph: ObservableObject {

    // MARK: Services (one instance each, process-wide)

    public let scope: any PowerScopeProviding
    public let persistence: PersistenceController
    public let cleanupEngine: CleanupEngine
    public let storeManager: StoreManager
    public let menuBarManager: MenuBarManager
    /// Buyout gate — read by `CleanupEngine` before every run. Purchased →
    /// unlimited; unpurchased → refusal (R5), which surfaces the paywall.
    public let quotaChecker: CleanupQuotaChecking
    /// Observers fanned out after each cleanup (menu bar, notification,
    /// widget snapshot, streaks, monthly report).
    public let eventSinks: [CleanupEventSink]
    // v2.5 Tab 化工具箱：每个工具一个常驻 VM（懒创建，Tab 切换不重建）。
    // P2 T9：工具表面随工具箱退役，仅粉碎窗（「+」菜单 / 整窗拖放共用）
    // 保留常驻装配；各工具的 VM/扫描器保留为逻辑层（画布扇出与设置页
    // 直接消费，测试直接构造）。
    private var toolVMCache: [String: AnyObject] = [:]

    private func cached<T: AnyObject>(_ key: String, _ make: () -> T) -> T {
        if let value = toolVMCache[key] as? T { return value }
        let value = make()
        toolVMCache[key] = value
        return value
    }

    func shredderVM() -> ShredderViewModel {
        cached("shredder") { ShredderViewModel() }
    }

    /// P2 T8 起维护任务由设置页承接（P2 T9 保留装配）：引擎接线 + 配额
    /// 超限弹买断墙，与其它清理面同一条引擎链。
    func maintenanceVM(onQuota: @escaping () -> Void) -> MaintenanceViewModel {
        cached("maintenance") {
            let vm = MaintenanceViewModel(engine: cleanupEngine)
            vm.onQuotaExhausted = onQuota
            return vm
        }
    }

    /// I5（P2 final）+ re-review residual：隐私清理的常驻 VM —— 统一预演链
    /// 的 CleanupViewModel **直接连 graph 引擎**（quota 买断门 + 事件 sink
    /// 与其它清理面同一条链），不再是 `CleanupEngine.standard()` 平行实例。
    /// 缓存复用：RootView（配额超限 → 买断墙路由）与设置页取**同一实例**
    /// —— 与 `maintenanceVM` 同模式；`onQuota` 以首次接线为准。
    func privacyCleanupVM(onQuota: @escaping () -> Void) -> PrivacyViewModel {
        cached("privacyCleanup") {
            let vm = PrivacyViewModel(cleanupViewModel: CleanupViewModel(engine: cleanupEngine))
            vm.cleanupViewModel.onQuotaExhausted = onQuota
            return vm
        }
    }

    // P1 T8: assistantVM() 已随聊天框退役删除——问答由下钻页内嵌的
    // AssistantNodePanelModel 承接（自带 matcher/builder，无共享状态）。
    // P2 T9: appUninstallVM/duplicatesVM/largeOldVM/photoCleanVM/
    // photoSimilarityVM/startupItemsVM 随工具表面退役删除（各 VM/扫描器
    // 保留为逻辑层，画布扇出与测试直接构造）。

    // MARK: Shared instance for App Intents / widget intents

    /// Lightweight graph for extension processes. UI builds its own graph
    /// in `kWiseApp` and must NOT use this (the UI graph owns observable
    /// state that SwiftUI observes).
    @MainActor
    public static let shared = AppGraph()

    public init(scope: (any PowerScopeProviding)? = nil, menuBar: MenuBarManager? = nil) {
        // Default to the AppScope-owned provider so every surface shares one
        // bookmark store and probe (MAS) — or the stateless full-access
        // provider in the direct edition (P3 dual-channel).
        self.scope = scope ?? AppScope.shared.scope
        self.persistence = PersistenceController(stack: CoreDataStack.shared)
        self.storeManager = StoreManager()
        // Created first: the menu bar is itself a CleanupEventSink and must
        // join the fan-out before the engine exists.
        let menuBarManager = menuBar ?? MenuBarManager()
        self.menuBarManager = menuBarManager
        // P1 T7 — the buyout is the gate. `hasPurchased` is MainActor-
        // isolated; hop back for the read. The launch refresh below (fix r1)
        // re-derives ownership from StoreKit before the first cleanup, so a
        // plain property read here is enough.
        self.quotaChecker = CleanupQuotaChecker { [storeManager] in
            await MainActor.run { storeManager.hasPurchased }
        }
        // The menu bar observes the same event stream (C-8 "最近清理" row);
        // the widget snapshot feed + streak ledger update the same way.
        self.eventSinks = [
            CleanupNotificationSink(),
            menuBarManager,
            WidgetSnapshotSink(),
            StreakSink(),
        ]
        self.cleanupEngine = CleanupEngine(
            persistence: persistence,
            quota: quotaChecker,
            sinks: eventSinks
        )
        // Fix r1 — re-derive ownership once per launch. The retired quota
        // closure used to call `checkSubscription()` before every cleanup
        // (self-healing stale state); without this launch refresh a
        // purchased user who relaunched the app was refused and shown the
        // paywall on their first cleanup.
        Task { await Self.refreshEntitlementsAtLaunch(storeManager) }
    }

    // MARK: Launch entitlement refresh

    /// One-shot ownership re-derivation, fired from `init` at launch (and
    /// therefore also for `AppGraph.shared` in App Intents / widget intent
    /// processes). Extracted as a static hook so the launch behavior is
    /// lockable in tests without constructing the full graph.
    static func refreshEntitlementsAtLaunch(_ store: StoreProtocol) async {
        await store.checkSubscription()
    }

    // MARK: Service factories

    /// Fresh single-shot scan orchestrator wired to the shared scope.
    public func makeScanOrchestrator() -> ScanOrchestrator {
        ScanOrchestrator(scope: scope)
    }

    /// Fresh scan engine wrapper around `makeScanOrchestrator()`.
    public func makeScanEngine() -> ScanEngine {
        ScanEngine(orchestrator: makeScanOrchestrator())
    }

    // P2 T5（R-统一）：Smart Care orchestrator 的清理引擎接线已删除 ——
    // 快捷回收统一走 CleanupViewModel 预演链（graph.cleanupEngine 仍服务
    // 该链），orchestrator 只保留扫描与推荐计算。
}

// MARK: - Environment access

private struct AppGraphKey: EnvironmentKey {
    // A graph value is required by the environment protocol; the real graph
    // is always injected from kWiseApp before any view reads it.
    static let defaultValue: AppGraph? = nil
}

public extension EnvironmentValues {
    /// The app's dependency graph. Force-unwrapped views would crash in
    /// previews, so access goes through `appGraph()` with a fallback builder.
    var appGraph: AppGraph? {
        get { self[AppGraphKey.self] }
        set { self[AppGraphKey.self] = newValue }
    }
}

/// Convenience accessor: returns the injected graph, or a lazily-built
/// standalone graph (previews, unit tests) when running without one.
@MainActor
public func appGraph(_ env: EnvironmentValues) -> AppGraph {
    env.appGraph ?? AppGraph()
}
