import SwiftUI
import DesignSystem

@MainActor
public final class ScanViewModel: ObservableObject {
    @Published public var progress: ScanProgress?
    @Published public var scanState: AppState.ScanState = .idle
    @Published public var scanResult: [DuplicateGroup] = []
    @Published public var largeFiles: [FileItem] = []
    @Published public var warnings: [ScanWarning] = []
    @Published public var summary: ScanSummary?
    @Published public var groupsFound = 0
    @Published public var elapsed: TimeInterval = 0

    private let orchestrator: ScanOrchestrator
    private var controller = ScanController()
    private var scanTask: Task<Void, Never>?
    private var elapsedTask: Task<Void, Never>?
    private var scanGeneration = UUID()
    /// Optional mirror of paid status. When set, the orchestrator wires up
    /// an `IncrementalIndex` so paid users get hash-cache hits on re-scan.
    /// Free users still get correct results — the index just stays inert.
    private let paidFlag: PaidUserFlag?
    /// Invoked on the main actor after a scan completes and its record is
    /// persisted. Lets the owning view publish results into `AppState` so
    /// `ResultView` (recreated per navigation) can pick them up.
    public var onScanCompleted: (([DuplicateGroup]) -> Void)?

    public init(orchestrator: ScanOrchestrator? = nil, paidFlag: PaidUserFlag? = nil) {
        self.paidFlag = paidFlag
        // Build a paid-aware orchestrator when a flag is provided, otherwise
        // default to the spec's "no incremental index" mode.
        if let orchestrator {
            self.orchestrator = orchestrator
        } else if let paidFlag {
            self.orchestrator = ScanOrchestrator(
                incrementalIndex: IncrementalIndex(
                    repository: IncrementalIndexRepositoryCoreData(),
                    isPaidUser: { paidFlag.value }
                )
            )
        } else {
            self.orchestrator = ScanOrchestrator()
        }
    }

    public func startScan(config: ProfileConfig) {
        scanState = .scanning(0)
        controller = ScanController()
        scanResult = []
        largeFiles = []
        warnings = []
        summary = nil
        progress = nil
        groupsFound = 0
        elapsed = 0
        elapsedTask?.cancel()
        let startDate = Date()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                self?.elapsed = Date().timeIntervalSince(startDate)
            }
        }

        scanTask?.cancel()
        let generation = UUID()
        scanGeneration = generation
        scanTask = Task {
            let stream = await orchestrator.run(config: config, controller: controller)
            for await event in stream {
                guard scanGeneration == generation else { return }
                switch event {
                case .progress(let p):
                    progress = p
                    scanState = .scanning(p.progress)
                case .group(let group):
                    scanResult.append(group)
                    groupsFound += 1
                case .largeFiles(let items):
                    largeFiles = items
                case .warning(let warning):
                    warnings.append(warning)
                case .failed(let message):
                    scanState = .failed(message)
                case .completed(let s):
                    summary = s
                }
            }

            guard let summary else {
                elapsedTask?.cancel()
                elapsedTask = nil
                return
            }
            elapsedTask?.cancel()
            elapsedTask = nil
            elapsed = Date().timeIntervalSince(startDate)
            try? await orchestrator.saveResults(
                scanResult,
                config: config,
                duration: summary.duration,
                filesScanned: summary.filesScanned
            )
            // Publish before flipping to .completed so ResultView never sees an
            // empty hand-off when the user reviews immediately after the spinner.
            onScanCompleted?(scanResult)
            scanState = .completed
        }
    }

    public func cancelScan() {
        controller.cancel()
        scanGeneration = UUID()
        scanTask?.cancel()
        elapsedTask?.cancel()
        elapsedTask = nil
        // Return to idle immediately; the cancelled stream must not publish a result.
        scanState = .idle
    }
}