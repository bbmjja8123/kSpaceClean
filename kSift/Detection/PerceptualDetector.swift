import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Finds visually similar images with a dHash coarse pass and Vision feature-print verification.
public actor PerceptualDetector {
    private struct Candidate {
        let item: FileItem
        let dHash: UInt64
    }

    private struct Pair: Hashable {
        let first: Int
        let second: Int

        init(_ lhs: Int, _ rhs: Int) {
            first = min(lhs, rhs)
            second = max(lhs, rhs)
        }
    }

    private final class BKNode {
        let hash: UInt64
        var indices: [Int]
        var children: [Int: BKNode] = [:]

        init(hash: UInt64, index: Int) {
            self.hash = hash
            indices = [index]
        }

        func insert(hash newHash: UInt64, index: Int) {
            let distance = (hash ^ newHash).nonzeroBitCount
            if distance == 0 {
                indices.append(index)
            } else if let child = children[distance] {
                child.insert(hash: newHash, index: index)
            } else {
                children[distance] = BKNode(hash: newHash, index: index)
            }
        }

        func matches(hash target: UInt64, maximumDistance: Int, into results: inout [Int]) {
            let distance = (hash ^ target).nonzeroBitCount
            if distance <= maximumDistance {
                results.append(contentsOf: indices)
            }
            let lowerBound = max(0, distance - maximumDistance)
            let upperBound = distance + maximumDistance
            for (edge, child) in children where edge >= lowerBound && edge <= upperBound {
                child.matches(hash: target, maximumDistance: maximumDistance, into: &results)
            }
        }
    }

    private let maximumHammingDistance: Int
    private let visionDistanceThreshold: Float
    private let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "webp"]

    public init(maximumHammingDistance: Int = 10, visionDistanceThreshold: Float = 0.6) {
        self.maximumHammingDistance = maximumHammingDistance
        self.visionDistanceThreshold = visionDistanceThreshold
    }

    /// Loads lightweight metadata and detects perceptual groups from file URLs.
    public func detect(_ urls: [URL], controller: ScanController) async -> [DuplicateGroup] {
        let items = urls.compactMap(FileItem.fromMetadata)
        return await detect(files: items, controller: controller)
    }

    /// Detects perceptual groups without decoding full-resolution source images.
    public func detect(files: [FileItem], controller: ScanController) async -> [DuplicateGroup] {
        var candidates: [Candidate] = []
        // Thumbnail cache shared between dHash (coarse filter) and featurePrint
        // (verification). ImageIO's CGImageSourceCreateThumbnailAtIndex decodes
        // a JPEG/PNG/HEIC preview — the most expensive per-file step in the
        // perceptual pass — so avoiding a second decode for any URL that
        // survives the dHash filter halves the ImageIO work.
        var thumbnails: [URL: CGImage] = [:]
        for item in files {
            guard !isCancelled(controller) else { return [] }
            guard supportedExtensions.contains(item.url.pathExtension.lowercased()),
                  let hash = dHash(of: item.url, thumbnailCache: &thumbnails) else {
                continue
            }
            candidates.append(Candidate(item: item, dHash: hash))
        }
        guard candidates.count > 1 else { return [] }

        let pairs = candidatePairs(in: candidates)
        guard !pairs.isEmpty else { return [] }

        var observations: [Int: VNFeaturePrintObservation] = [:]
        var acceptedPairs: [(Pair, Float)] = []
        var parents = Array(candidates.indices)

        func root(of index: Int) -> Int {
            var current = index
            while parents[current] != current {
                current = parents[current]
            }
            return current
        }

        func join(_ lhs: Int, _ rhs: Int) {
            let leftRoot = root(of: lhs)
            let rightRoot = root(of: rhs)
            if leftRoot != rightRoot {
                parents[rightRoot] = leftRoot
            }
        }

        for pair in pairs.sorted(by: { ($0.first, $0.second) < ($1.first, $1.second) }) {
            guard !isCancelled(controller) else { return makeGroups(candidates, parents, acceptedPairs) }

            if observations[pair.first] == nil {
                observations[pair.first] = featurePrint(
                    of: candidates[pair.first].item.url,
                    thumbnailCache: &thumbnails
                )
            }
            if observations[pair.second] == nil {
                observations[pair.second] = featurePrint(
                    of: candidates[pair.second].item.url,
                    thumbnailCache: &thumbnails
                )
            }
            guard let first = observations[pair.first],
                  let second = observations[pair.second],
                  let distance = distance(from: first, to: second),
                  distance <= visionDistanceThreshold else {
                continue
            }

            join(pair.first, pair.second)
            acceptedPairs.append((pair, distance))
        }

        return makeGroups(candidates, parents, acceptedPairs)
    }

    func dHash(of url: URL, thumbnailCache: inout [URL: CGImage]) -> UInt64? {
        guard let image = thumbnail(of: url, maximumPixelSize: 256, thumbnailCache: &thumbnailCache) else { return nil }
        return dHash(of: image)
    }

    func dHash(of image: CGImage) -> UInt64? {
        guard let context = CGContext(
            data: nil,
            width: 9,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 9,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: 9, height: 8))
        guard let data = context.data else { return nil }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var hash: UInt64 = 0
        var bit = 0

        for row in 0..<8 {
            for column in 0..<8 {
                if pixels[row * 9 + column] > pixels[row * 9 + column + 1] {
                    hash |= UInt64(1) << UInt64(bit)
                }
                bit += 1
            }
        }
        return hash
    }

    func hammingDistance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }

    private func candidatePairs(in candidates: [Candidate]) -> Set<Pair> {
        guard let first = candidates.first else { return [] }
        let tree = BKNode(hash: first.dHash, index: 0)
        var pairs = Set<Pair>()

        for index in candidates.indices.dropFirst() {
            var matches: [Int] = []
            tree.matches(
                hash: candidates[index].dHash,
                maximumDistance: maximumHammingDistance,
                into: &matches
            )
            for match in matches {
                pairs.insert(Pair(match, index))
            }
            tree.insert(hash: candidates[index].dHash, index: index)
        }
        return pairs
    }

    private func featurePrint(of url: URL, thumbnailCache: inout [URL: CGImage]) -> VNFeaturePrintObservation? {
        guard let image = thumbnail(of: url, maximumPixelSize: 256, thumbnailCache: &thumbnailCache) else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }

    private func distance(
        from lhs: VNFeaturePrintObservation,
        to rhs: VNFeaturePrintObservation
    ) -> Float? {
        var distance: Float = 0
        do {
            try lhs.computeDistance(&distance, to: rhs)
            return distance
        } catch {
            return nil
        }
    }

    private func thumbnail(of url: URL, maximumPixelSize: Int, thumbnailCache: inout [URL: CGImage]) -> CGImage? {
        if let cached = thumbnailCache[url] { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        thumbnailCache[url] = image
        return image
    }

    private func makeGroups(
        _ candidates: [Candidate],
        _ parents: [Int],
        _ acceptedPairs: [(Pair, Float)]
    ) -> [DuplicateGroup] {
        func root(of index: Int) -> Int {
            var current = index
            while parents[current] != current {
                current = parents[current]
            }
            return current
        }

        let components = Dictionary(grouping: candidates.indices, by: root)
        return components.values.compactMap { indices in
            guard indices.count > 1 else { return nil }
            let rootIndex = root(of: indices[0])
            let distances = acceptedPairs.compactMap { element -> Float? in
                let (pair, distance) = element
                guard root(of: pair.first) == rootIndex,
                      root(of: pair.second) == rootIndex else {
                    return nil
                }
                return distance
            }
            guard !distances.isEmpty else { return nil }
            let averageDistance = Double(distances.reduce(0, +) / Float(distances.count))
            let items = indices.map { candidates[$0].item }.sorted { $0.size > $1.size }
            let total = items.reduce(Int64(0)) { partial, item in
                let addition = partial.addingReportingOverflow(item.size)
                return addition.overflow ? Int64.max : addition.partialValue
            }
            let reclaimable = max(0, total - (items.map(\.size).max() ?? 0))

            return DuplicateGroup(
                id: UUID(),
                category: .perceptual,
                totalSize: reclaimable,
                fileCount: items.count,
                files: items,
                categoryEvidence: .perceptualSimilarity(
                    distance: averageDistance,
                    method: .visionFeaturePrint
                ),
                similarity: max(0, min(1, 1 - averageDistance))
            )
        }
        .sorted { ($0.similarity ?? 0) > ($1.similarity ?? 0) }
    }


    private func isCancelled(_ controller: ScanController) -> Bool {
        controller.isCancelled || Task.isCancelled
    }
}
