import Foundation
import Combine

/// SwiftUI-facing wrapper around ``SmartCareOrchestrator``.
///
/// Two reasons this exists separately from the orchestrator:
/// 1. `SmartCareHeroView` (root of the home surface) owns this VM via
///    `@StateObject`; the orchestrator's `@MainActor` lifecycle is identical
///    but the project convention keeps SwiftUI glue in a `*ViewModel` file.
/// 2. Exposes high-level intent (`runSmartCare`, `beginQuickCleanExecution`,
///    `completeQuickClean`, `reset`) so the view layer doesn't need to know
///    the state machine details.
///
/// P2 T5（R-统一）：执行不再走本 VM —— `.confirming` 由根部预演 sheet
/// 接管，确认后统一走 `CleanupViewModel` 预演链（quota / paywall / sinks
/// 都在那条链上），跑完由 RootView 回填结果。推荐项经 `recommendedTargets`
/// 供预演入参。
///
/// - SeeAlso: ``SmartCareOrchestrator``, `docs/superpowers/plans/2026-08-09-kwise-v1.5-plan.md` Task 3.
@MainActor
public final class SmartCareViewModel: ObservableObject {
    private let orchestrator: SmartCareOrchestrator

    /// Forwards the orchestrator's published state to SwiftUI.
    @Published public private(set) var state: SmartCareState

    /// Convenience bool — `true` while the orchestrator is in
    /// `.scanning`, `.recommending`, or `.cleaning`.
    public var isBusy: Bool {
        switch state {
        case .scanning, .recommending, .cleaning:
            return true
        default:
            return false
        }
    }

    init(scanResultsViewModel: ScanResultsViewModel? = nil) {
        let orch = SmartCareOrchestrator(scanResultsViewModel: scanResultsViewModel)
        self.orchestrator = orch
        // Seed state synchronously so SwiftUI has a non-optional initial value.
        self.state = orch.state
        orch.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                // Forward the state VALUE, not just the invalidation — without
                // this copy `state` stays at its seeded `.idle` forever and
                // the hero UI never reflects scan/clean progress.
                self.state = self.orchestrator.state
                self.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Intent

    /// Hero CTA. Triggers `Smart Care`: scan → auto-pick → `.confirming`
    /// （随后由根部预演 sheet 接管，R-统一）。
    public func runSmartCare() {
        orchestrator.start()
        state = orchestrator.state
    }

    /// 推荐项 → 预演入参（C4：危险项已在 adapter 门控中排除）。
    public var recommendedTargets: [CleanupTarget] {
        orchestrator.recommendedTargets
    }

    /// 预演 sheet 确认后由 RootView 调用：进入 `.cleaning`，随后统一链执行。
    public func beginQuickCleanExecution() {
        orchestrator.beginExecution()
        state = orchestrator.state
    }

    /// 统一链跑完后的结果回填 —— `doneHero` 展示真实释放字节。
    public func completeQuickClean(freedBytes: Int64, durationSeconds: TimeInterval) {
        orchestrator.completeExecution(freedBytes: freedBytes,
                                       durationSeconds: durationSeconds)
        state = orchestrator.state
    }

    /// 统一链失败时的回填 —— `failedHero` 展示。
    public func failQuickClean(message: String) {
        orchestrator.failExecution(message: message)
        state = orchestrator.state
    }

    /// Re-arm for another run.
    public func reset() {
        orchestrator.reset()
        state = orchestrator.state
    }

    /// Late-bind the scan view model after SwiftUI environment resolution.
    func attach(scanResultsViewModel: ScanResultsViewModel) {
        orchestrator.attach(scanResultsViewModel: scanResultsViewModel)
        state = orchestrator.state
    }
}