import Foundation
import CommonUtils
import DetectionCore

// MARK: - Public Models (UI contract)

/// A group of files that share the same content, identified by identical hash.
public struct DuplicateGroup: Identifiable, Sendable {
    public let id = UUID()
    public let fileSize: Int64
    public var files: [DuplicatedFile]
    public var isExpanded: Bool = true
    /// `true` when the duplicates are APFS clonefile copies — trashing all
    /// but one reclaims almost nothing, so the UI must say so honestly.
    public var isAPFSCloneSet: Bool = false

    /// Total space that could be reclaimed if all but one file were removed.
    public var totalWasted: Int64 {
        fileSize * Int64(max(0, files.count - 1))
    }

    public init(fileSize: Int64, files: [DuplicatedFile], isExpanded: Bool = true) {
        self.fileSize = fileSize
        self.files = files
        self.isExpanded = isExpanded
    }
}

/// A single file that is part of a duplicate group.
public struct DuplicatedFile: Identifiable, Sendable {
    public let id = UUID()
    public let url: URL
    public let size: Int64
    public let modificationDate: Date
    public var isSelected: Bool = false

    public var path: String { url.path }
    public var fileName: String { url.lastPathComponent }

    public init(url: URL, size: Int64, modificationDate: Date, isSelected: Bool = false) {
        self.url = url
        self.size = size
        self.modificationDate = modificationDate
        self.isSelected = isSelected
    }
}

// MARK: - DuplicateScanner (DetectionCore adapter)

/// Duplicate scanner backed by the DetectionCore engine (kSift's pipeline:
/// FileWalker → 4-stage ByteIdenticalDetector [size → fingerprint → SHA-256
/// → byte compare] → APFSCloneDetector annotation).
///
/// The old in-app implementation used a hybrid MD5+CRC32 heuristic; the
/// DetectionCore pipeline is strictly stronger (byte-verified before any
/// group is declared) and flags clonefile sets so reclaimable space is
/// reported honestly.
///
/// Results are delivered as an `AsyncStream<DuplicateGroup>`. Progress is
/// reported on the optional `AsyncStream<Double>.Continuation` (0.0 … 1.0).
public final class DuplicateScanner: @unchecked Sendable {

    public init() {}

    /// Begins a byte-verified duplicate scan across the given root paths.
    ///
    /// - Parameters:
    ///   - paths: Root URLs to scan (kWise passes PowerScope-resolved dirs only).
    ///   - progress: An optional continuation that receives values in [0.0, 1.0].
    /// - Returns: An `AsyncStream` that yields a `DuplicateGroup` for each
    ///   byte-verified duplicate set.
    public func scan(
        paths: [URL],
        progress: AsyncStream<Double>.Continuation?
    ) -> AsyncStream<DuplicateGroup> {
        AsyncStream { continuation in
            Task {
                await self.performScan(
                    paths: paths,
                    progress: progress,
                    continuation: continuation
                )
            }
        }
    }

    private func performScan(
        paths: [URL],
        progress: AsyncStream<Double>.Continuation?,
        continuation: AsyncStream<DuplicateGroup>.Continuation
    ) async {
        progress?.yield(0.0)

        let controller = ScanController()
        let walker = FileWalker()
        let target = ScanTarget(
            directories: paths.map(\.path),
            exclusions: [],
            minFileSize: 1
        )

        // Stage 1 — enumerate via the shared FileEnumerator-backed walker.
        let urls: [URL]
        do {
            urls = try await walker.walk(target: target, controller: controller) { _ in }
        } catch {
            continuation.finish()
            return
        }
        progress?.yield(0.3)

        guard !urls.isEmpty else {
            progress?.yield(1.0)
            continuation.finish()
            return
        }

        // Stage 2 — byte-verified grouping (fingerprint → SHA-256 → compare).
        let byteDetector = ByteIdenticalDetector()
        var groups = await byteDetector.detect(urls, controller: controller)
        progress?.yield(0.85)

        // Stage 3 — APFS clonefile annotation (honest reclaimable-size math).
        groups = await APFSCloneDetector().annotate(groups)

        for siftGroup in groups {
            let files = siftGroup.files.map { item in
                DuplicatedFile(
                    url: item.url,
                    size: item.size,
                    modificationDate: item.modificationDate ?? Date()
                )
            }
            guard let size = files.first?.size else { continue }
            var group = DuplicateGroup(fileSize: size, files: files)
            group.isAPFSCloneSet = siftGroup.files.contains { $0.isAPFSClone }
            continuation.yield(group)
        }

        progress?.yield(1.0)
        continuation.finish()
    }
}
