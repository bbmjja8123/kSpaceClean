import Darwin
import FileScanner
import Foundation
import UniformTypeIdentifiers

/// Detects byte-identical files using size, fingerprint, full SHA-256, and byte comparison.
public actor ByteIdenticalDetector {
    /// A file that could not be verified without interrupting the rest of the scan.
    public struct Failure: Sendable, Equatable {
        public let url: URL
        public let reason: String
    }

    private struct Candidate {
        let result: HashVerifier.VerifyResult
        let metadata: URLResourceValues
        /// True when the hashes came from the incremental index rather than disk.
        let fromCache: Bool
    }

    private let verifier: HashVerifier
    private let minimumSize: Int64

    public private(set) var failures: [Failure] = []

    /// Fingerprint + full-hash pairs for every URL the detector actually verified
    /// this scan, including cache hits. Populated incrementally as Candidates are
    /// built; cleared on each `detect` invocation. Callers (notably
    /// DirectoryDedupDetector) consume this to avoid re-hashing files whose
    /// content proof is already established.
    public private(set) var verifiedCache: [URL: CachedVerification] = [:]

    public init(verifier: HashVerifier = HashVerifier(), minimumSize: Int64 = 1) {
        self.verifier = verifier
        self.minimumSize = minimumSize
    }

    /// Returns only groups whose members passed all four verification stages.
    ///
    /// - Parameter cache: Files whose (size, mtime, inode) signature is unchanged
    ///   reuse their stored fingerprint + hash instead of being re-read. All-cache
    ///   groups skip the final byte comparison: equal unchanged hashes imply
    ///   identical bytes.
    public func detect(
        _ urls: [URL],
        controller: ScanController,
        cache: [URL: CachedVerification] = [:]
    ) async -> [DuplicateGroup] {
        failures = []
        verifiedCache = [:]
        var sizeBuckets: [Int64: [URL]] = [:]

        for url in urls {
            guard !isCancelled(controller) else { return [] }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                let size = Int64(values.fileSize ?? 0)
                guard size >= minimumSize else { continue }
                sizeBuckets[size, default: []].append(url)
            } catch {
                recordFailure(url, error)
            }
        }

        var groups: [DuplicateGroup] = []
        for (expectedSize, sizeCandidates) in sizeBuckets where sizeCandidates.count > 1 {
            guard !isCancelled(controller) else { return groups }

            var fingerprintBuckets: [String: [URL]] = [:]
            for url in sizeCandidates {
                guard !isCancelled(controller) else { return groups }
                do {
                    let fingerprint: String
                    if let cached = cache[url] {
                        fingerprint = cached.fingerprint
                    } else {
                        fingerprint = try await verifier.fingerprint(of: url)
                    }
                    fingerprintBuckets[fingerprint, default: []].append(url)
                } catch {
                    recordFailure(url, error)
                }
            }

            for (fingerprint, fingerprintCandidates) in fingerprintBuckets where fingerprintCandidates.count > 1 {
                guard !isCancelled(controller) else { return groups }

                var hashBuckets: [String: [Candidate]] = [:]
                for url in fingerprintCandidates {
                    guard !isCancelled(controller) else { return groups }
                    do {
                        let cached = cache[url]
                        let fullHash: String
                        if let cached {
                            fullHash = cached.hash
                        } else {
                            fullHash = try await verifier.fullHash(of: url)
                        }
                        verifiedCache[url] = CachedVerification(
                            fingerprint: fingerprint,
                            hash: fullHash
                        )
                        let keys: Set<URLResourceKey> = [
                            .fileSizeKey,
                            .contentModificationDateKey,
                            .creationDateKey,
                            .totalFileAllocatedSizeKey,
                        ]
                        let metadata = try url.resourceValues(forKeys: keys)
                        guard Int64(metadata.fileSize ?? 0) == expectedSize else {
                            failures.append(Failure(url: url, reason: "file changed while scanning"))
                            continue
                        }
                        let result = HashVerifier.VerifyResult(
                            url: url,
                            size: expectedSize,
                            fingerprint: fingerprint,
                            fullHash: fullHash,
                            duration: 0
                        )
                        hashBuckets[fullHash, default: []].append(Candidate(
                            result: result, metadata: metadata, fromCache: cached != nil
                        ))
                    } catch {
                        recordFailure(url, error)
                    }
                }

                for (hash, hashCandidates) in hashBuckets where hashCandidates.count > 1 {
                    guard !isCancelled(controller) else { return groups }
                    let verifiedPartitions = await byteVerifiedPartitions(hashCandidates, controller: controller)
                    for partition in verifiedPartitions where partition.count > 1 {
                        let files = partition
                            .map(makeFileItem)
                            .sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
                        let multiplier = Int64(files.count - 1)
                        let reclaimable = expectedSize.multipliedReportingOverflow(by: multiplier)
                        groups.append(DuplicateGroup(
                            id: UUID(),
                            category: .identical,
                            totalSize: reclaimable.overflow ? Int64.max : reclaimable.partialValue,
                            fileCount: files.count,
                            files: files,
                            categoryEvidence: .byteIdentical(sha256: hash, byteVerified: true)
                        ))
                    }
                }
            }
        }

        return groups.sorted {
            if $0.totalSize == $1.totalSize {
                return ($0.files.first?.url.path ?? "") < ($1.files.first?.url.path ?? "")
            }
            return $0.totalSize > $1.totalSize
        }
    }

    private func byteVerifiedPartitions(
        _ candidates: [Candidate],
        controller: ScanController
    ) async -> [[Candidate]] {
        // When every member came from the incremental index, equal unchanged
        // hashes already prove identical bytes; skip the byte comparison pass.
        if candidates.allSatisfy(\.fromCache) {
            return [candidates]
        }

        var partitions: [[Candidate]] = []

        for candidate in candidates {
            guard !isCancelled(controller) else { return partitions }
            var matchingIndex: Int?
            for index in partitions.indices {
                if await verifier.byteEqual(partitions[index][0].result.url, candidate.result.url) {
                    matchingIndex = index
                    break
                }
            }

            if let matchingIndex {
                partitions[matchingIndex].append(candidate)
            } else {
                partitions.append([candidate])
            }
        }
        return partitions
    }

    private func makeFileItem(_ candidate: Candidate) -> FileItem {
        let url = candidate.result.url
        return FileItem(
            id: UUID(),
            url: url,
            size: candidate.result.size,
            modificationDate: candidate.metadata.contentModificationDate ?? .distantPast,
            creationDate: candidate.metadata.creationDate,
            hash: candidate.result.fullHash,
            fingerprint: candidate.result.fingerprint,
            inode: inode(of: url),
            physicalSize: candidate.metadata.totalFileAllocatedSize.map(Int64.init),
            fileType: UTType(filenameExtension: url.pathExtension)
        )
    }

    private func inode(of url: URL) -> UInt64? {
        var fileInfo = stat()
        let status: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            return Darwin.lstat(path, &fileInfo)
        }
        return status == 0 ? UInt64(fileInfo.st_ino) : nil
    }

    private func isCancelled(_ controller: ScanController) -> Bool {
        controller.isCancelled || Task.isCancelled
    }

    private func recordFailure(_ url: URL, _ error: Error) {
        failures.append(Failure(url: url, reason: error.localizedDescription))
    }
}
