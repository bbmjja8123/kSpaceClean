import CryptoKit
import FileScanner
import Foundation
import UniformTypeIdentifiers

/// Detects whole directories with identical relative paths and byte-identical contents.
public actor DirectoryDedupDetector {
    private struct Snapshot {
        let directory: URL
        let entries: [String: FileItem]
        let contentHash: String
        let totalSize: Int64
    }

    private let verifier: HashVerifier

    public init(verifier: HashVerifier = HashVerifier()) {
        self.verifier = verifier
    }

    /// Convenience entry point for callers that have not yet produced verified file metadata.
///
/// - Parameter verifiedCache: Map of URL → CachedVerification for files whose
///   fingerprint + SHA-256 have already been computed by an earlier stage
///   (typically ByteIdenticalDetector). URLs present here skip the
///   `verifier.verify(...)` call entirely, saving a streaming SHA-256 read
///   per cached file. URLs not in the map are verified on demand.
public func detect(
        _ urls: [URL],
        roots: [URL] = [],
        controller: ScanController,
        verifiedCache: [URL: CachedVerification] = [:]
    ) async -> [DuplicateGroup] {
        var files: [FileItem] = []
        for url in urls {
            guard !isCancelled(controller) else { return [] }
            let result: HashVerifier.VerifyResult
            if let cached = verifiedCache[url] {
                let size: Int64
                do {
                    size = Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                } catch {
                    continue
                }
                result = HashVerifier.VerifyResult(
                    url: url,
                    size: size,
                    fingerprint: cached.fingerprint,
                    fullHash: cached.hash,
                    duration: 0
                )
            } else {
                do {
                    result = try await verifier.verify(url)
                } catch {
                    continue
                }
            }
            guard let values = try? url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .creationDateKey,
                .totalFileAllocatedSizeKey,
            ]) else { continue }
            files.append(FileItem(
                id: UUID(),
                url: url,
                size: result.size,
                modificationDate: values.contentModificationDate ?? .distantPast,
                creationDate: values.creationDate,
                hash: result.fullHash,
                fingerprint: result.fingerprint,
                physicalSize: values.totalFileAllocatedSize.map(Int64.init),
                fileType: UTType(filenameExtension: url.pathExtension)
            ))
        }
        return await detect(files: files, roots: roots, controller: controller)
    }

    /// Builds O(n) directory content hashes from previously verified files.
    public func detect(
        files: [FileItem],
        roots: [URL],
        controller: ScanController
    ) async -> [DuplicateGroup] {
        let effectiveRoots = normalizedRoots(roots, files: files)
        guard !effectiveRoots.isEmpty else { return [] }

        var entriesByDirectory: [URL: [String: FileItem]] = [:]
        for file in files {
            guard !isCancelled(controller) else { return [] }
            guard file.hash != nil,
                  let root = containingRoot(for: file.url, roots: effectiveRoots) else {
                continue
            }

            var directory = normalizedDirectory(file.url.deletingLastPathComponent())
            while isContained(directory, in: root) {
                let relativePath = relativePath(from: directory, to: file.url)
                entriesByDirectory[directory, default: [:]][relativePath] = file
                if directory == root { break }
                let parent = normalizedDirectory(directory.deletingLastPathComponent())
                guard parent != directory else { break }
                directory = parent
            }
        }

        let snapshots = entriesByDirectory.compactMap(makeSnapshot)
        let hashBuckets = Dictionary(grouping: snapshots, by: \.contentHash)
        var groups: [DuplicateGroup] = []

        for (contentHash, candidates) in hashBuckets where candidates.count > 1 {
            guard !isCancelled(controller) else { return groups }
            let partitions = await byteVerifiedPartitions(candidates, controller: controller)
            for partition in partitions where partition.count > 1 {
                let directoryItems = partition
                    .map(makeDirectoryItem)
                    .sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
                let oneDirectorySize = partition[0].totalSize
                let reclaimable = oneDirectorySize.multipliedReportingOverflow(
                    by: Int64(partition.count - 1)
                )
                groups.append(DuplicateGroup(
                    id: UUID(),
                    category: .directoryDedup,
                    totalSize: reclaimable.overflow ? Int64.max : reclaimable.partialValue,
                    fileCount: directoryItems.count,
                    files: directoryItems,
                    categoryEvidence: .directoryDuplicate(
                        contentHash: contentHash,
                        fileCount: partition[0].entries.count
                    )
                ))
            }
        }

        return groups.sorted { $0.totalSize > $1.totalSize }
    }

    private func makeSnapshot(_ pair: (key: URL, value: [String: FileItem])) -> Snapshot? {
        guard !pair.value.isEmpty else { return nil }
        var hasher = SHA256()
        var totalSize: Int64 = 0

        for relativePath in pair.value.keys.sorted() {
            guard let file = pair.value[relativePath], let hash = file.hash else { return nil }
            hasher.update(data: Data("\(relativePath)\t\(file.size)\t\(hash)\n".utf8))
            totalSize = totalSize.addingReportingOverflow(file.size).overflow
                ? Int64.max
                : totalSize + file.size
        }

        let contentHash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return Snapshot(
            directory: pair.key,
            entries: pair.value,
            contentHash: contentHash,
            totalSize: totalSize
        )
    }

    private func byteVerifiedPartitions(
        _ snapshots: [Snapshot],
        controller: ScanController
    ) async -> [[Snapshot]] {
        var partitions: [[Snapshot]] = []
        for snapshot in snapshots {
            guard !isCancelled(controller) else { return partitions }
            var matchingIndex: Int?
            for index in partitions.indices {
                if await directoriesEqual(partitions[index][0], snapshot, controller: controller) {
                    matchingIndex = index
                    break
                }
            }
            if let matchingIndex {
                partitions[matchingIndex].append(snapshot)
            } else {
                partitions.append([snapshot])
            }
        }
        return partitions
    }

    private func directoriesEqual(
        _ lhs: Snapshot,
        _ rhs: Snapshot,
        controller: ScanController
    ) async -> Bool {
        guard Set(lhs.entries.keys) == Set(rhs.entries.keys) else { return false }
        for path in lhs.entries.keys {
            guard !isCancelled(controller),
                  let left = lhs.entries[path],
                  let right = rhs.entries[path],
                  left.size == right.size,
                  await verifier.byteEqual(left.url, right.url) else {
                return false
            }
        }
        return true
    }

    private func makeDirectoryItem(_ snapshot: Snapshot) -> FileItem {
        let values = try? snapshot.directory.resourceValues(forKeys: [
            .contentModificationDateKey,
            .creationDateKey,
        ])
        return FileItem(
            id: UUID(),
            url: snapshot.directory,
            size: snapshot.totalSize,
            modificationDate: values?.contentModificationDate ?? .distantPast,
            creationDate: values?.creationDate,
            hash: snapshot.contentHash,
            fileType: .folder
        )
    }

    private func normalizedRoots(_ roots: [URL], files: [FileItem]) -> [URL] {
        if !roots.isEmpty {
            return roots.map(normalizedDirectory)
        }
        guard var components = files.first?.url.standardizedFileURL.pathComponents else { return [] }
        for file in files.dropFirst() {
            let other = file.url.standardizedFileURL.pathComponents
            components = Array(zip(components, other).prefix { $0.0 == $0.1 }.map(\.0))
        }
        guard !components.isEmpty else { return [] }
        return [URL(fileURLWithPath: NSString.path(withComponents: components))]
    }

    /// Directory URLs must have a single canonical form. `URL(fileURLWithPath:)` stats the
    /// filesystem to decide the trailing slash, so `isDirectory` is passed explicitly to keep the
    /// result independent of whether the directory still exists on disk.
    private func normalizedDirectory(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true)
    }

    private func containingRoot(for file: URL, roots: [URL]) -> URL? {
        roots
            .filter { isContained(file.standardizedFileURL, in: $0) }
            .max { $0.path.count < $1.path.count }
    }

    private func isContained(_ url: URL, in root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }

    private func relativePath(from directory: URL, to file: URL) -> String {
        let directoryComponents = directory.standardizedFileURL.pathComponents
        let fileComponents = file.standardizedFileURL.pathComponents
        return fileComponents.dropFirst(directoryComponents.count).joined(separator: "/")
    }

    private func isCancelled(_ controller: ScanController) -> Bool {
        controller.isCancelled || Task.isCancelled
    }
}
