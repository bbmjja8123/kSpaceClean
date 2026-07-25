import CryptoKit
import FileScanner
import Foundation

public actor DirectoryDedupDetector {
    private let hasher: FileHasher

    public init(hasher: FileHasher = FileHasher()) {
        self.hasher = hasher
    }

    /// Detects files with identical content across different directories.
    /// O(n): hashes every file but returns only cross-directory duplicates.
    public func detect(_ urls: [URL], controller: ScanController) async throws -> [DuplicateGroup] {
        var hashBuckets: [String: [URL]] = [:]
        for url in urls {
            guard !controller.isCancelled else { return [] }
            if let hash = try? await hasher.hash(file: url) {
                hashBuckets[hash, default: []].append(url)
            }
        }

        var groups: [DuplicateGroup] = []
        for (hash, files) in hashBuckets where files.count > 1 {
            guard !controller.isCancelled else { return groups }
            // Only keep cross-directory duplicates
            let dirs = Set(files.map { $0.deletingLastPathComponent().path })
            guard dirs.count > 1 else { continue }

            let totalSize = files.reduce(0) { $0 + (try? FileManager.default.attributesOfItem(atPath: $1.path)[.size] as? Int64 ?? 0) ?? 0 }
            let fileItems = files.map { url in
                FileItem(id: UUID(), url: url, size: 0, modificationDate: Date(), hash: hash)
            }
            groups.append(DuplicateGroup(
                id: UUID(), category: .directoryDedup, totalSize: totalSize,
                fileCount: files.count, files: fileItems
            ))
        }
        return groups
    }
}
