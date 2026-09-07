import AVFoundation
import CoreGraphics
import Foundation

/// Source of per-video frame hashes and light metadata. Abstracted so
/// tests drive grouping with synthetic hashes — no media files needed.
public protocol VideoFrameHashing: Sendable {
    /// `sampleCount` dHashes of evenly spaced frames.
    func frameHashes(for url: URL, sampleCount: Int) async throws -> [UInt64]
    func duration(of url: URL) async -> TimeInterval?
}

/// AVFoundation-backed sampler. Keyframe-only decoding via infinite
/// seek tolerance keeps hashing fast; a handful of evenly spaced frames
/// is enough to separate true re-encodes from unrelated clips.
public struct AVAssetFrameHasher: VideoFrameHashing {
    public init() {}

    public func frameHashes(for url: URL, sampleCount: Int) async throws -> [UInt64] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard duration.seconds.isFinite, duration.seconds > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Infinite tolerance = keyframe-only decodes, an order of
        // magnitude cheaper than exact-time seeks.
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        generator.maximumSize = CGSize(width: 64, height: 64)

        let count = max(2, sampleCount)
        let times: [CMTime] = (0..<count).map { index in
            CMTime(seconds: duration.seconds * Double(index) / Double(count - 1), preferredTimescale: 600)
        }

        var hashes: [UInt64] = []
        hashes.reserveCapacity(count)
        // The async sequence yields (requestedTime, image, actualTime);
        // failed decodes simply don't appear.
        for await frame in generator.images(for: times) {
            if let hash = PerceptualHashing.dHash(of: try frame.image) {
                hashes.append(hash)
            }
        }
        return hashes
    }

    public func duration(of url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        return duration.seconds.isFinite && duration.seconds > 0 ? duration.seconds : nil
    }
}

/// Groups videos whose sampled frame hashes match across a sufficient
/// ratio of frames — the "similar video" tier none of the category
/// competitors do well. Mirrors `PerceptualDetector`'s BK-tree +
/// union-find structure, with a size/duration pre-filter in front of
/// the O(n²·k²) frame comparison.
public actor SimilarVideoDetector {
    private let hasher: any VideoFrameHashing
    private let sampleCount: Int
    private let maximumFrameHammingDistance: Int
    private let minimumMatchedFrameRatio: Double
    private let sizeTolerance: Double
    private let durationTolerance: Double
    private let supportedExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv", "mpg", "mpeg",
    ]

    public init(
        hasher: any VideoFrameHashing = AVAssetFrameHasher(),
        sampleCount: Int = 8,
        maximumFrameHammingDistance: Int = 10,
        minimumMatchedFrameRatio: Double = 0.7,
        sizeTolerance: Double = 0.2,
        durationTolerance: Double = 0.05
    ) {
        self.hasher = hasher
        self.sampleCount = sampleCount
        self.maximumFrameHammingDistance = maximumFrameHammingDistance
        self.minimumMatchedFrameRatio = minimumMatchedFrameRatio
        self.sizeTolerance = sizeTolerance
        self.durationTolerance = durationTolerance
    }

    /// Groups candidate video files into `.similarVideo` duplicate groups.
    public func detect(files: [FileItem], controller: ScanController) async -> [DuplicateGroup] {
        let candidates = files.filter { supportedExtensions.contains($0.url.pathExtension.lowercased()) }
        guard candidates.count > 1 else { return [] }

        // Sample each video once; failures (corrupt/unsupported) drop out.
        var samples: [(file: FileItem, hashes: [UInt64], duration: TimeInterval?)] = []
        for file in candidates {
            guard !isCancelled(controller) else { return [] }
            let hashes = (try? await hasher.frameHashes(for: file.url, sampleCount: sampleCount)) ?? []
            guard !hashes.isEmpty else { continue }
            let duration = await hasher.duration(of: file.url)
            samples.append((file, hashes, duration))
        }
        guard samples.count > 1 else { return [] }

        // Union-find over accepted pairs (same structure as the image
        // perceptual detector).
        var parent = Array(samples.indices)
        func find(_ x: Int) -> Int {
            var root = x
            while parent[root] != root { root = parent[root] }
            var current = x
            while parent[current] != root {
                let next = parent[current]
                parent[current] = root
                current = next
            }
            return root
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
        }

        for i in samples.indices {
            guard !isCancelled(controller) else { return [] }
            for j in samples.indices where j > i {
                guard sizesCompatible(samples[i].file, samples[j].file) else { continue }
                guard durationsCompatible(samples[i].duration, samples[j].duration) else { continue }
                if matchedFrameRatio(samples[i].hashes, samples[j].hashes) >= minimumMatchedFrameRatio {
                    union(i, j)
                }
            }
        }

        var clusters: [Int: [Int]] = [:]
        for index in samples.indices {
            clusters[find(index), default: []].append(index)
        }

        var groups: [DuplicateGroup] = []
        for cluster in clusters.values where cluster.count > 1 {
            guard !isCancelled(controller) else { return groups }
            let files = cluster
                .map { samples[$0].file }
                .sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
            let totalSize = files.reduce(Int64(0)) { $0 + $1.size }
            let reclaimable = files.dropFirst().reduce(Int64(0)) { $0 + $1.size }
            groups.append(DuplicateGroup(
                id: UUID(),
                category: .similarVideo,
                totalSize: reclaimable,
                fileCount: files.count,
                files: files,
                categoryEvidence: .similarVideo(
                    matchedFrameRatio: minimumMatchedFrameRatio,
                    frameCount: sampleCount
                )
            ))
        }
        return groups.sorted { $0.totalSize > $1.totalSize }
    }

    private func sizesCompatible(_ a: FileItem, _ b: FileItem) -> Bool {
        let smaller = Double(min(a.size, b.size))
        let larger = Double(max(a.size, b.size))
        guard smaller > 0 else { return larger == 0 }
        return (larger - smaller) / larger <= sizeTolerance
    }

    private func durationsCompatible(_ a: TimeInterval?, _ b: TimeInterval?) -> Bool {
        // Unknown duration on either side: let frame matching decide.
        guard let a, let b else { return true }
        let smaller = min(a, b)
        let larger = max(a, b)
        guard larger > 0 else { return true }
        return (larger - smaller) / larger <= durationTolerance
    }

    /// Ratio of frames in the shorter hash list with a neighbour in the
    /// other list within `maximumFrameHammingDistance`.
    private func matchedFrameRatio(_ lhs: [UInt64], _ rhs: [UInt64]) -> Double {
        let (shorter, longer) = lhs.count <= rhs.count ? (lhs, rhs) : (rhs, lhs)
        guard !shorter.isEmpty else { return 0 }
        var matched = 0
        for hash in shorter {
            if longer.contains(where: { PerceptualHashing.hammingDistance(hash, $0) <= maximumFrameHammingDistance }) {
                matched += 1
            }
        }
        return Double(matched) / Double(shorter.count)
    }

    private func isCancelled(_ controller: ScanController) -> Bool {
        controller.isCancelled || Task.isCancelled
    }
}
