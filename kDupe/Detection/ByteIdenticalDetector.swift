import CryptoKit
import FileScanner
import Foundation

public actor ByteIdenticalDetector {
    private let hasher: FileHasher

    public init(hasher: FileHasher = FileHasher()) {
        self.hasher = hasher
    }

    public func detect(_ urls: [URL], controller: ScanController) async throws -> [DuplicateGroup] {
        // Phase 1: group by file size
        var sizeGroups: [Int64: [URL]] = [:]
        for url in urls {
            guard !controller.isCancelled else { return [] }
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attrs[.size] as? Int64 ?? 0
            sizeGroups[size, default: []].append(url)
        }

        // Phase 2: hash candidates (>1 same-size file)
        var groups: [DuplicateGroup] = []
        for (size, candidates) in sizeGroups where candidates.count > 1 {
            guard !controller.isCancelled else { return groups }
            var hashBuckets: [String: [URL]] = [:]
            for url in candidates {
                guard !controller.isCancelled else { return groups }
                if let hash = try? await hasher.hash(file: url) {
                    hashBuckets[hash, default: []].append(url)
                }
            }
            for (_, files) in hashBuckets where files.count > 1 {
                let fileItems = files.map { url in
                    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                    return FileItem(
                        id: UUID(),
                        url: url,
                        size: size,
                        modificationDate: attrs?[.modificationDate] as? Date ?? Date(),
                        hash: try? await hasher.hash(file: url)
                    )
                }
                groups.append(DuplicateGroup(
                    id: UUID(),
                    category: .identical,
                    totalSize: size * Int64(files.count - 1),
                    fileCount: files.count,
                    files: fileItems
                ))
            }
        }
        return groups
    }
}
