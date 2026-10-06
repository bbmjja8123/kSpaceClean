import Foundation
import Combine

/// 3-step Smart Care state machine (v1.5).
///
/// State transitions (P2 T5 R-统一 起):
/// ```
///   .idle
///     → .scanning(progress)       (user taps hero CTA)
///   .scanning(progress)
///     → .recommending              (scan engine reports completion)
///     → .failed(message)           (FDA required, scan errored, etc.)
///   .recommending
///     → .confirming(items, bytes)  (auto-pick algorithm yields N items)
///   .confirming                    (预演 sheet 接管 —— orchestrator 停在这里，
///                                   绝不自行动手)
///     → .cleaning(progress)        (sheet 确认后宿主调 beginExecution)
///   .cleaning
///     → .done(freedBytes, dur)     (统一链跑完，宿主回填 completeExecution)
///     → .failed(message)           (宿主回填 failExecution)
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

/// Drives the Smart Care scan → recommend pipeline.
///
/// P2 T5（R-统一，废除 P1 两层信任裁定）：orchestrator 只保留**扫描与
/// 推荐计算** —— `.confirming` 由根部的预演 sheet（``CleanupRehearsalSheet``）
/// 接管，确认后执行统一走 `CleanupViewModel.makeRehearsal(targets:)` +
/// `executeConfirmedCleanup` 预演链。orchestrator 不再持有清理引擎，
/// 旧的 `confirm()` 直执行路径已删除；宿主在统一链跑完后用
/// ``beginExecution()`` / ``completeExecution(freedBytes:durationSeconds:)`` /
/// ``failExecution(message:)`` 回填 `doneHero` / `failedHero`。
///
/// - SeeAlso: `IntentScanAdapter.recommendedEntries`（推荐计算单源）。
@MainActor
final class SmartCareOrchestrator: ObservableObject {
    @Published public private(set) var state: SmartCareState = .idle
    @Published private(set) var recommendedItems: [ScanResult] = []

    private weak var scanResultsViewModel: ScanResultsViewModel?

    /// Designated initializer. The view model can also be attached later
    /// via ``attach(scanResultsViewModel:)`` when SwiftUI environment
    /// resolution is preferred.
    init(scanResultsViewModel: ScanResultsViewModel? = nil) {
        self.scanResultsViewModel = scanResultsViewModel
    }

    /// 推荐项 → 预演入参（P2 T5）：hero 快捷回收的 sheet 用这批 targets
    /// 调 `CleanupViewModel.makeRehearsal(targets:)`。C4：risk 恒为
    /// `.recommended` —— 危险项已被 `recommendedEntries` 的
    /// `riskLevel.defaultChecked` 门控排除。
    public var recommendedTargets: [CleanupTarget] {
        recommendedItems.map { entry in
            CleanupTarget(url: URL(fileURLWithPath: entry.path),
                          size: entry.fileSize,
                          risk: .recommended)
        }
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

    /// 预演 sheet 确认后由宿主调用：进入 `.cleaning`，随后统一链
    /// （`CleanupViewModel.executeConfirmedCleanup`）在跑。执行中状态由
    /// sheet 的 `isExecuting` 渲染，orchestrator 不触碰引擎。
    public func beginExecution() {
        state = .cleaning(progress: 0)
    }

    /// 统一链跑完后的结果回填（P2 T5）：`doneHero` 展示的真实释放字节
    /// 来自 `CleanupOutcome.freedBytes`，不再由 orchestrator 自行测量。
    public func completeExecution(freedBytes: Int64, durationSeconds: TimeInterval) {
        state = .done(freedBytes: freedBytes, durationSeconds: durationSeconds)
    }

    /// 统一链失败（`lastOutcome == nil`）时的回填；`failedHero` 展示。
    public func failExecution(message: String) {
        state = .failed(message: message)
    }

    /// Returns to `.idle` so the hero CTA can re-trigger the flow.
    public func reset() {
        state = .idle
        recommendedItems = []
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
    /// leaf entry whose risk level is default-checked. Delegates to
    /// `IntentScanAdapter.recommendedEntries` — the single-source traversal
    /// shared with the AppIntents (P1 T9 双引擎退役).
    ///
    /// C4 note: the gate is `riskLevel.defaultChecked` (not the legacy
    /// `isRecommended` flag), so a leaf whose flag and risk level disagree
    /// (e.g. a dangerous file carrying a recommended flag) is never picked.
    private func computeRecommendedPicks(scanVM: ScanResultsViewModel) -> [ScanResult] {
        IntentScanAdapter.recommendedEntries(in: scanVM.categories)
    }
}