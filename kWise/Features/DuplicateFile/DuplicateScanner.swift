import Foundation
import CommonUtils
import DetectionCore

// MARK: - DuplicateScanner (ScanOrchestrator adapter, v2.3 Phase 2)

/// Duplicate scanner backed by the FULL DetectionCore pipeline
/// (`ScanOrchestrator`): FileWalker → ByteIdenticalDetector (size →
/// fingerprint → SHA-256 → byte compare) → APFSCloneDetector → Perceptual /
/// NameHeuristic detectors. Selection strategies are applied by the
/// `ToolboxGroup` mapping layer (`Features/Common/Models/ToolboxGroupModels.swift`).
///
/// The engine's `ScanEvent` stream is forwarded verbatim — the view model
/// maps events into `ToolboxGroup`s.
public final class DuplicateScanner: @unchecked Sendable {

    public init() {}

    /// Runs the duplicate pipeline over `paths`.
    ///
    /// - Parameters:
    ///   - paths: Root URLs (kWise passes PowerScope-resolved dirs only).
    ///   - preset: Similar-photo grouping aggressiveness.
    ///   - strategy: Which copy to keep (applied by the mapping layer).
    /// - Returns: The engine's `ScanEvent` stream, forwarded verbatim.
    public func scan(paths: [URL],
                     preset: SimilarityPreset,
                     strategy: SelectionStrategy) -> AsyncStream<DetectionCore.ScanEvent> {
        let orchestrator = DetectionCore.ScanOrchestrator(
            perceptualDetector: DetectionCore.PerceptualDetector(
                maximumHammingDistance: preset.maximumHammingDistance,
                visionDistanceThreshold: preset.visionDistanceThreshold
            ),
            largeFileDetector: nil,
            similarVideoDetector: nil,
            repository: NullDuplicateRepository()
        )
        let config = DetectionCore.ProfileConfig(
            type: .custom,
            customDirectories: paths.map(\.path),
            exclusions: [],
            minFileSize: 1_048_576,   // 1 MB floor — sub-MB dupes are noise
            enablePerceptualScan: true,
            enableBuildArtifacts: false,
            selectionStrategy: strategy,
            similarityPreset: preset,
            largeFileSizeThreshold: .max
        )
        let controller = DetectionCore.ScanController()
        return AsyncStream { continuation in
            Task {
                let events = await orchestrator.run(config: config, controller: controller)
                for await event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}
