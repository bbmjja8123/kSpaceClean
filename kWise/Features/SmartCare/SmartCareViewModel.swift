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

    public init(scanResultsViewModel: ScanResultsViewModel? = nil) {
        let orch = SmartCareOrchestrator(scanResultsViewModel: scanResultsViewModel)
        self.orchestrator = orch
        // Seed state synchronously so SwiftUI has a non-optional initial value.
        self.state = orch.state
        orch.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Intent

    /// Hero CTA. Triggers `Smart Care`: scan → auto-pick → confirm.
    public func runSmartCare() {
        orch.start()
    }

    /// User confirms the recommended picks. Cleans them up.
    public func confirm() {
        orch.confirm()
    }

    /// Re-arm for another run.
    public func reset() {
        orch.reset()
    }

    /// Late-bind the scan view model after SwiftUI environment resolution.
    public func attach(scanResultsViewModel: ScanResultsViewModel) {
        orch.attach(scanResultsViewModel: scanResultsViewModel)
    }
}