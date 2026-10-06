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
    /// 进行中管线的代次（P2 T5 fix r1，Important 1）：`start()` 递增并捕获、
    /// `reset()`/`attach()` 递增作废 —— 在途 `runPipeline` 在每个挂起点后
    /// 核对代次，被取消的管线静默放弃。取消必须真的取消：用户取消后管线
    /// 绝不允许落进 `.confirming`（否则根部会弹出模态预演 sheet）。
    private var pipelineGeneration = 0

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
        // 换绑定即作废旧 scanVM 的在途管线（与 reset 同一代次语义）。
        pipelineGeneration += 1
        state = .idle
        recommendedItems = []
    }

    /// Hero CTA entry point. Triggers the scan → recommend pipeline.
    public func start() {
        guard let scanVM = scanResultsViewModel else {
            state = .failed(message: "扫描模块未连接")
            return
        }
        pipelineGeneration += 1
        let generation = pipelineGeneration
        state = .scanning(progress: 0)
        scanVM.startScan()
        Task { @MainActor in
            await self.runPipeline(scanVM: scanVM, generation: generation)
        }
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

    /// Returns to `.idle` and **aborts any in-flight pipeline** (P2 T5 fix r1):
    /// the generation bump makes `runPipeline` bail out at its next checkpoint
    /// instead of walking into `.confirming`. Cancelling must actually cancel.
    public func reset() {
        pipelineGeneration += 1
        state = .idle
        recommendedItems = []
    }

    // MARK: - Pipeline

    /// Polls the injected view model's `isScanning` flag, mirrors progress
    /// onto the orchestrator's `.scanning(progress:)` state, then runs the
    /// auto-pick on completion and transitions to `.confirming`.
    ///
    /// fix r1（Important 1）：`generation` 与 ``pipelineGeneration`` 不一致
    /// 即中途取消 —— 在每个挂起点后核对并放弃（state 已被 `reset()` 归
    /// `.idle`，这里绝不再写）。
    private func runPipeline(scanVM: ScanResultsViewModel, generation: Int) async {
        guard generation == pipelineGeneration else { return }
        // Mirror scan progress at ~10 Hz while the engine is busy.
        while scanVM.isScanning {
            state = .scanning(progress: scanVM.progress)
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard generation == pipelineGeneration else { return }
        }
        guard generation == pipelineGeneration else { return }
        state = .scanning(progress: 1.0)

        // Sandboxed / scope-limited: surface the gap instead of presenting
        // an empty results page (PowerScope-era copy — no FDA promises).
        if scanVM.needsFullDiskAccess {
            state = .failed(message: "需要主目录访问权限，请在设置中授权后重试")
            return
        }

        // Auto-pick: collect all leaf entries where
        // `ScanResult.isRecommended == true`.
        guard generation == pipelineGeneration else { return }
        state = .recommending
        let picks = computeRecommendedPicks(scanVM: scanVM)
        guard generation == pipelineGeneration else { return }
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