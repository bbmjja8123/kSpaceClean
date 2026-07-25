import SwiftUI
import DesignSystem

@MainActor
public final class ScanViewModel: ObservableObject {
    @Published public var progress: ScanProgress?
    @Published public var scanState: AppState.ScanState = .idle
    @Published public var scanResult: [DuplicateGroup] = []

    private let orchestrator: ScanOrchestrator
    private var controller = ScanController()

    public init(orchestrator: ScanOrchestrator = ScanOrchestrator()) {
        self.orchestrator = orchestrator
    }

    public func startScan(config: ProfileConfig) {
        scanState = .scanning(0)
        controller = ScanController()
        scanResult = []

        Task {
            var allGroups: [DuplicateGroup] = []
            let startTime = Date()

            let stream = await orchestrator.run(config: config, controller: controller)
            for await p in stream {
                progress = p
                if case .completed = p.phase {
                    scanState = .completed
                }
            }
            let duration = Date().timeIntervalSince(startTime)
            try? await orchestrator.saveResults(allGroups, config: config, duration: duration, filesScanned: progress?.filesScanned ?? 0)
            scanResult = allGroups
        }
    }

    public func cancelScan() {
        controller.cancel()
        scanState = .idle
    }
}
