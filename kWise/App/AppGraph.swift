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

    public let scope: PowerScope
    public let persistence: PersistenceController
    public let cleanupEngine: CleanupEngine
    public let storeManager: StoreManager
    public let menuBarManager: MenuBarManager
    /// Free-tier quota gate — read by `CleanupEngine` before every run.
    public let quotaChecker: CleanupQuotaChecking
    /// Observers fanned out after each cleanup (quota ledger today; streaks,
    /// monthly report and widget snapshot join in later phases).
    public let eventSinks: [CleanupEventSink]
    /// Live scan results the assistant reads for data-backed answers.
    /// Weak — RootView owns the scan VM's lifetime.
    weak var assistantScanVM: ScanResultsViewModel?

    // v2.5 Tab 化工具箱：每个工具一个常驻 VM（懒创建，Tab 切换不重建）。
    private var toolVMCache: [String: AnyObject] = [:]

    private func cached<T: AnyObject>(_ key: String, _ make: () -> T) -> T {
        if let value = toolVMCache[key] as? T { return value }
        let value = make()
        toolVMCache[key] = value
        return value
    }

    func appUninstallVM(onQuota: @escaping () -> Void) -> AppUninstallViewModel {
        cached("appUninstall") {
            let vm = AppUninstallViewModel(engine: cleanupEngine)
            vm.onQuotaExhausted = onQuota
            return vm
        }
    }

    func duplicatesVM(onQuota: @escaping () -> Void) -> DuplicateViewModel {
        cached("duplicates") {
            let vm = DuplicateViewModel(engine: cleanupEngine)
            vm.onQuotaExhausted = onQuota
            return vm
        }
    }

    func largeOldVM(onQuota: @escaping () -> Void) -> LargeOldViewModel {
        cached("largeOld") {
            let vm = LargeOldViewModel(engine: cleanupEngine)
            vm.onQuotaExhausted = onQuota
            return vm
        }
    }

    func photoCleanVM(onQuota: @escaping () -> Void) -> PhotoCleanViewModel {
        cached("photoClean") {
            let vm = PhotoCleanViewModel(engine: cleanupEngine)
            vm.onQuotaExhausted = onQuota
            return vm
        }
    }

    func photoSimilarityVM(onQuota: @escaping () -> Void) -> PhotoSimilarityViewModel {
        cached("photoSimilarity") {
            let vm = PhotoSimilarityViewModel(engine: cleanupEngine)
            vm.onQuotaExhausted = onQuota
            return vm
        }
    }

    func shredderVM() -> ShredderViewModel {
        cached("shredder") { ShredderViewModel() }
    }

    func startupItemsVM() -> StartupItemsViewModel {
        cached("startupItems") { StartupItemsViewModel() }
    }

    func maintenanceVM(onQuota: @escaping () -> Void) -> MaintenanceViewModel {
        cached("maintenance") {
            let vm = MaintenanceViewModel(engine: cleanupEngine)
            vm.onQuotaExhausted = onQuota
            return vm
        }
    }

    func assistantVM() -> AssistantViewModel {
        cached("assistant") { AssistantViewModel() }
    }

    // MARK: Shared instance for App Intents / widget intents

    /// Lightweight graph for extension processes. UI builds its own graph
    /// in `kWiseApp` and must NOT use this (the UI graph owns observable
    /// state that SwiftUI observes).
    @MainActor
    public static let shared = AppGraph()

    public init(scope: PowerScope? = nil, menuBar: MenuBarManager? = nil) {
        // Default to the AppScope-owned actor so every surface shares one
        // bookmark store and probe.
        self.scope = scope ?? AppScope.shared.scope
        self.persistence = PersistenceController(stack: CoreDataStack.shared)
        self.storeManager = StoreManager()
        // Created first: the menu bar is itself a CleanupEventSink and must
        // join the fan-out before the engine exists.
        let menuBarManager = menuBar ?? MenuBarManager()
        self.menuBarManager = menuBarManager
        self.quotaChecker = CleanupQuotaChecker { [storeManager] in
            await storeManager.checkSubscription()
            // `isSubscribed` is MainActor-isolated; hop back for the read.
            return await MainActor.run { storeManager.isSubscribed }
        }
        let quotaLedger = FreeQuotaStore.standard()
        // The menu bar observes the same event stream (C-8 "最近清理" row);
        // the widget snapshot feed + streak ledger update the same way.
        self.eventSinks = [
            QuotaRecordSink(store: quotaLedger),
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

    /// Fresh Smart Care orchestrator over the shared cleanup engine.
    func makeSmartCareOrchestrator(scanVM: ScanResultsViewModel? = nil) -> SmartCareOrchestrator {
        SmartCareOrchestrator(scanResultsViewModel: scanVM, cleanupEngine: cleanupEngine)
    }
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
