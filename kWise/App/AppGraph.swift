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
