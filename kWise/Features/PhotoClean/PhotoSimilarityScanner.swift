// kWise/Features/PhotoClean/PhotoSimilarityScanner.swift
//
// 相似照片扫描引擎 (v2.3 Phase 3) — DetectionCore PerceptualDetector over
// PowerScope-granted picture directories. Zero network: similarity is
// computed entirely on-device (dHash + Vision feature print).
import Foundation
import DetectionCore
import PowerScope

// MARK: - Config

struct PhotoSimilarityConfig: Sendable {
    var directories: [URL]
    var preset: SimilarityPreset
    /// Photos below this size rarely matter for cleanup.
    var minFileSize: Int64 = 128 * 1024
}

// MARK: - Scanner

/// Finds visually similar photos (screenshots piles, burst leftovers,
/// re-downloads) by running the DetectionCore perceptual pipeline over
/// candidate directories the current scope can actually read.
final class PhotoSimilarityScanner: @unchecked Sendable {

    /// Candidate photo directories inside the granted home scope, filtered
    /// by `capability.canRead` — container-only users get an empty list and
    /// the UI shows a grant CTA instead of a fake "0 files" result.
    static func candidateDirectories(capability: ScopeCapability) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Pictures/Screenshots", isDirectory: true),
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Downloads", isDirectory: true),
            home.appendingPathComponent("Pictures", isDirectory: true),
        ]
        return candidates.filter { capability.canRead($0) }
    }

    private let walker = FileWalker()

    func scan(config: PhotoSimilarityConfig,
              controller: ScanController,
              progress: @escaping @Sendable (Double, String?) -> Void) async -> [DetectionCore.DuplicateGroup] {
        guard !config.directories.isEmpty else { return [] }
        progress(0.0, nil)

        let target = DetectionCore.ScanTarget(
            directories: config.directories.map(\.path),
            exclusions: [],
            minFileSize: config.minFileSize
        )
        let urls: [URL]
        do {
            urls = try await walker.walk(target: target, controller: controller) { result in
                // Coarse enumeration progress: 0–40% of the run.
                progress(0.4, result.url.lastPathComponent)
            }
        } catch {
            return []
        }
        guard !urls.isEmpty else {
            progress(1.0, nil)
            return []
        }
        progress(0.4, nil)

        let preset = config.preset
        let detector = PerceptualDetector(
            maximumHammingDistance: preset.maximumHammingDistance,
            visionDistanceThreshold: preset.visionDistanceThreshold
        )
        // Grouping phase: 40–100%.
        progress(0.5, nil)
        let groups = await detector.detect(urls, controller: controller)
        progress(1.0, nil)
        return groups
    }
}
