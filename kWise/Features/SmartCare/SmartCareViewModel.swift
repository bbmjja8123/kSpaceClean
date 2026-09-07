import Foundation
import Combine

/// SwiftUI-facing wrapper around ``SmartCareOrchestrator``.
///
/// Two reasons this exists separately from the orchestrator:
/// 1. `SmartCareHeroView` (root of the home surface) owns this VM via
///    `@StateObject`; the orchestrator's `@MainActor` lifecycle is identical
///    but the project convention keeps SwiftUI glue in a `*ViewModel` file.
/// 2. Exposes high-level intent (`runSmartCare`, `confirm`, `reset`) so the
///    view layer doesn't need to know the state machine details.
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
                if case .done = self.state, self.orchestrator.lastRunQuotaExhausted {
                    self.orchestrator.resetQuotaFlag()
                    self.onQuotaExhausted?()
                }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private var cancellables: Set<AnyCancellable> = []

    /// Invoked when the confirmed run hit the free-quota ceiling — the root
    /// presents the paywall (never the view itself).
    public var onQuotaExhausted: (() -> Void)?

    /// Re-point at the shared graph engine (v2.0 Phase 1 DI unification).
    func useEngine(_ engine: CleanupEngine) {
        orchestrator.useEngine(engine)
    }

    // MARK: - Intent

    /// Hero CTA. Triggers `Smart Care`: scan → auto-pick → confirm.
    public func runSmartCare() {
        orchestrator.start()
        state = orchestrator.state
    }

    /// User confirms the recommended picks. Cleans them up.
    public func confirm() {
        orchestrator.confirm()
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