import Foundation
import CommonCrypto
import CommonUtils

// MARK: - CRC32 on Data

extension Data {
    /// Computes a table-based CRC32 checksum of the data.
    public var crc32: UInt32 {
        let table = CRC32.table
        return withUnsafeBytes { rawBuf in
            var crc: UInt32 = 0xFFFF_FFFF
            guard let base = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            for i in 0 ..< count {
                let idx = Int((crc ^ UInt32(base[i])) & 0xFF)
                crc = (crc >> 8) ^ table[idx]
            }
            return crc ^ 0xFFFF_FFFF
        }
    }

    private enum CRC32 {
        static let table: [UInt32] = {
            var tbl = [UInt32](repeating: 0, count: 256)
            for i in 0 ..< 256 {
                var crc = UInt32(i)
                for _ in 0 ..< 8 {
                    crc = (crc & 1) != 0 ? (0xEDB8_8320 ^ (crc >> 1)) : (crc >> 1)
                }
                tbl[i] = crc
            }
            return tbl
        }()
    }
}

// MARK: - MD5 on Data

extension Data {
    /// Returns the MD5 hex digest of the data using CommonCrypto.
    var md5String: String {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        withUnsafeBytes { rawBuf in
            _ = CC_MD5(rawBuf.baseAddress, CC_LONG(count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Public Models

/// A group of files that share the same content, identified by identical hash.
public struct DuplicateGroup: Identifiable, Sendable {
    public let id = UUID()
    public let fileSize: Int64
    public var files: [DuplicatedFile]
    public var isExpanded: Bool = true

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

// MARK: - DuplicateScanner

/// Two-stage duplicate file scanner.
///
/// **Stage 1** walks the supplied directories via `FileManager.enumerator`, groups files by
/// their `fileSize`, and keeps only groups containing more than one file.
///
/// **Stage 2** computes a content hash for every file in each candidate group:
/// - Files < 10 MB → full MD5 digest.
/// - Files ≥ 10 MB → hybrid hash: `MD5(first10MB)_CRC32(remainder)`.
///
/// Results are delivered as an `AsyncStream<DuplicateGroup>`. Progress is reported on the
/// optional `AsyncStream<Double>.Continuation` (0.0 … 1.0).
public final class DuplicateScanner: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: Public API

    /// Begins a two-stage scan across the given root paths.
    ///
    /// - Parameters:
    ///   - paths: Root URLs to scan.
    ///   - progress: An optional continuation that receives values in [0.0, 1.0].
    /// - Returns: An `AsyncStream` that yields a `DuplicateGroup` for each hash-matched set.
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

    // MARK: Stage 1 — Size-based grouping

    private func performScan(
        paths: [URL],
        progress: AsyncStream<Double>.Continuation?,
        continuation: AsyncStream<DuplicateGroup>.Continuation
    ) async {
        progress?.yield(0.0)

        var sizeGroups: [Int64: [URL]] = [:]

        for root in paths {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(
                    forKeys: Set([.isRegularFileKey, .fileSizeKey])
                ),
                    values.isRegularFile == true,
                    let fileSize = values.fileSize,
                    fileSize > 0
                else { continue }

                sizeGroups[Int64(fileSize), default: []].append(fileURL)
            }
        }

        let candidateGroups = sizeGroups.filter { $0.value.count > 1 }
        progress?.yield(0.3)

        guard !candidateGroups.isEmpty else {
            continuation.finish()
            return
        }

        // MARK: Stage 2 — Hash-based matching

        let groups = Array(candidateGroups)
        let totalGroups = groups.count

        for (idx, (size, urls)) in groups.enumerated() {
            let hashGroups = await computeHashes(for: urls)

            for (_, hashUrls) in hashGroups where hashUrls.count > 1 {
                let files: [DuplicatedFile] = hashUrls.map { url in
                    let modDate = (
                        try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    )?.contentModificationDate ?? Date()
                    return DuplicatedFile(url: url, size: size, modificationDate: modDate)
                }

                let group = DuplicateGroup(fileSize: size, files: files)
                continuation.yield(group)
            }

            let stage2Progress = 0.3 + (Double(idx + 1) / Double(totalGroups)) * 0.7
            progress?.yield(stage2Progress)
        }

        progress?.yield(1.0)
        continuation.finish()
    }

    // MARK: Per-group hashing

    private func computeHashes(for urls: [URL]) async -> [String: [URL]] {
        var hashGroups: [String: [URL]] = [:]
        for url in urls {
            let hash = await computeFileHash(url: url)
            hashGroups[hash, default: []].append(url)
        }
        return hashGroups
    }

    private func computeFileHash(url: URL) async -> String {
        let fileSize = url.fileSize
        let tenMB: Int64 = 10 * 1024 * 1024

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return UUID().uuidString
        }
        defer { try? handle.close() }

        if fileSize < tenMB {
            // Full MD5 for files under 10 MB.
            guard let data = try? handle.readToEnd() else { return UUID().uuidString }
            return data.md5String
        } else {
            // Hybrid: MD5(first 10 MB) + "_" + CRC32(remainder)
            guard let firstChunk = try? handle.read(upToCount: Int(tenMB)),
                  let remainder = try? handle.readToEnd()
            else { return UUID().uuidString }

            let md5 = firstChunk.md5String
            let crc = remainder.crc32
            return "\(md5)_\(String(format: "%08x", crc))"
        }
    }
}
