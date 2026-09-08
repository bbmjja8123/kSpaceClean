import Foundation
import Combine

/// 3-step Smart Care state machine (v1.5).
///
/// State transitions:
/// ```
///   .idle
///     → .scanning(progress)       (user taps hero CTA)
///   .scanning(progress)
///     → .recommending              (scan engine reports completion)
///     → .failed(message)           (FDA required, scan errored, etc.)
///   .recommending
///     → .confirming(items, bytes)  (auto-pick algorithm yields N items)
///   .confirming
///     → .cleaning(progress)        (user confirms)
///   .cleaning
///     → .done(freedBytes, dur)     (cleanup engine returns outcome)
///     → .failed(message)           (cleanup errored)
///   any
///     → .idle                      (reset)
/// ```
///
/// - SeeAlso: ``SmartCareOrchestrator``, `docs/superpowers/plans/2026-08-09-kwise-v1.5-plan.md` Task 3.
public enum SmartCareState: Equatable {
    case idle
    case scanning(progress: Double)
    case recommending
    case confirming(itemCount: Int, totalSize: Int64)
    case cleaning(progress: Double)
    case done(freedBytes: Int64, durationSeconds: TimeInterval)
    case failed(message: String)
}

/// Drives the Smart Care 3-step pipeline.
///
/// Phase B scope (Task 3):
/// * Owns the state machine and the `start()` / `confirm()` / `reset()` entry points.
/// * Delegates actual scanning to an injected ``ScanResultsViewModel`` (which
///   in turn owns the lower-level `ScanEngine`).
/// * Recommended-pick algorithm: filters the engine's leaf entries to
///   `ScanResult.isRecommended == true` (set by `ScanRule`).
///
/// Follow-up tasks hook ``confirm()`` into `CleanupEngine.cleanup(targets:)`
/// (Task 5) and wire `SmartCareHeroView`'s CTA (Task 4).
@MainActor
final class SmartCareOrchestrator: ObservableObject {
    @Published public private(set) var state: SmartCareState = .idle
    @Published private(set) var recommendedItems: [ScanResult] = []

    private weak var scanResultsViewModel: ScanResultsViewModel?
    /// Injected cleanup engine. Defaults to a fresh instance backed by the
    /// shared `PersistenceController`; tests can substitute a stub. The app
    /// root re-points it at the graph engine (quota + sinks) in `.onAppear`.
    private(set) var cleanupEngine: CleanupEngine
    /// `true` when the most recent `.done` run left targets behind because
    /// the free-tier quota ran out. The view model surfaces the paywall.
    @Published public private(set) var lastRunQuotaExhausted = false

    /// Designated initializer. The view model can also be attached later
    /// via ``attach(scanResultsViewModel:)`` when SwiftUI environment
    /// resolution is preferred.
    init(scanResultsViewModel: ScanResultsViewModel? = nil,
                cleanupEngine: CleanupEngine? = nil) {
        self.scanResultsViewModel = scanResultsViewModel
        // `CleanupEngine.standard()` needs MainActor isolation — resolving
        // here (inside a @MainActor init) keeps the default optional.
        self.cleanupEngine = cleanupEngine ?? CleanupEngine.standard()
    }

    /// Re-point at the shared graph engine (v2.0 Phase 1 DI unification).
    func useEngine(_ engine: CleanupEngine) {
        self.cleanupEngine = engine
    }

    /// Late-binds a scan view model after construction.
    func attach(scanResultsViewModel: ScanResultsViewModel) {
        self.scanResultsViewModel = scanResultsViewModel
        state = .idle
        recommendedItems = []
    }

    /// Hero CTA entry point. Triggers the scan → recommend pipeline.
    public func start() {
        guard let scanVM = scanResultsViewModel else {
            state = .failed(message: "扫描模块未连接")
            return
        }
        state = .scanning(progress: 0)
        scanVM.startScan()
        Task { @MainActor in await self.runPipeline(scanVM: scanVM) }
    }

    /// User confirms the recommended picks. Phase C-3 polish (post-Phase D):
    /// real `CleanupEngine.cleanup(targets:)` invocation. Returns the actual
    /// `CleanupOutcome.freedBytes` so the user sees a truthful
    /// "X.XX GB freed" within ~1.5s.
    public func confirm() {
        state = .cleaning(progress: 0)
        Task { @MainActor in
            let started = Date()
            let targets = recommendedItems.map { entry -> CleanupTarget in
                let url = URL(fileURLWithPath: entry.path)
                return CleanupTarget(url: url, size: entry.fileSize, risk: .recommended)
            }
            do {
                let outcome = try await cleanupEngine.cleanup(targets: targets)
                lastRunQuotaExhausted = outcome.quotaExhausted
                state = .done(
                    freedBytes: outcome.freedBytes,
                    durationSeconds: Date().timeIntervalSince(started)
                )
            } catch {
                state = .failed(message: "清理失败：\(error.localizedDescription)")
            }
        }
    }

    /// Returns to `.idle` so the hero CTA can re-trigger the flow.
    public func reset() {
        state = .idle
        recommendedItems = []
    }

    /// Clears the one-shot paywall flag after the view model has reacted.
    func resetQuotaFlag() {
        lastRunQuotaExhausted = false
    }

    // MARK: - Pipeline

    /// Polls the injected view model's `isScanning` flag, mirrors progress
    /// onto the orchestrator's `.scanning(progress:)` state, then runs the
    /// auto-pick on completion and transitions to `.confirming`.
    private func runPipeline(scanVM: ScanResultsViewModel) async {
        // Mirror scan progress at ~10 Hz while the engine is busy.
        while scanVM.isScanning {
            state = .scanning(progress: scanVM.progress)
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        state = .scanning(progress: 1.0)

        // Sandboxed / scope-limited: surface the gap instead of presenting
        // an empty results page (PowerScope-era copy — no FDA promises).
        if scanVM.needsFullDiskAccess {
            state = .failed(message: "需要主目录访问权限，请在设置中授权后重试")
            return
        }

        // Auto-pick: collect all leaf entries where
        // `ScanResult.isRecommended == true`.
        state = .recommending
        let picks = computeRecommendedPicks(scanVM: scanVM)
        recommendedItems = picks

        let totalSize = picks.reduce(Int64(0)) { $0 + $1.fileSize }
        state = .confirming(itemCount: picks.count, totalSize: totalSize)
    }

    /// Recommended-pick algorithm: every category → subcategory → action →
    /// leaf entry whose `isRecommended` flag is set.
    private func computeRecommendedPicks(scanVM: ScanResultsViewModel) -> [ScanResult] {
        var picks: [ScanResult] = []
        for category in scanVM.categories {
            for sub in category.subItems {
                for action in sub.actions {
                    for entry in action.results where entry.isRecommended {
                        picks.append(entry)
                    }
                }
            }
        }
        return picks
    }
}