import FileScanner
import Foundation

/// Thread-safe counter used inside `@Sendable` enumeration callbacks.
private final class EnumerationCounter: @unchecked Sendable {
    private var count = 0
    private let lock = NSLock()

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}

/// Returns true for cancellation errors, which end the scan quietly rather than
/// surfacing a `.failed` event.
private func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let scanError = error as? FileEnumerator.ScanError, case .cancelled = scanError { return true }
    return false
}


public actor ScanOrchestrator {
    private let fileWalker: any FileWalkerProtocol
    private let byteDetector: ByteIdenticalDetector
    private let cloneDetector: APFSCloneDetector
    private let dirDedupDetector: DirectoryDedupDetector
    private let perceptualDetector: PerceptualDetector
    private let largeFileDetector: LargeFileDetector
    private let buildArtifactDetector: BuildArtifactDetector
    private let rawJPEGDetector: RawJPEGPairDetector
    private let repository: DuplicateRepositoryProtocol
    private let incrementalIndex: (any IncrementalIndexProtocol)?

    /// Progress events emitted during enumeration (every N files, not per file).
    private let enumerationProgressInterval = 256

    public init(
        fileWalker: any FileWalkerProtocol = FileWalker(),
        byteDetector: ByteIdenticalDetector = ByteIdenticalDetector(),
        cloneDetector: APFSCloneDetector = APFSCloneDetector(),
        dirDedupDetector: DirectoryDedupDetector = DirectoryDedupDetector(),
        perceptualDetector: PerceptualDetector = PerceptualDetector(),
        largeFileDetector: LargeFileDetector = LargeFileDetector(),
        buildArtifactDetector: BuildArtifactDetector = BuildArtifactDetector(),
        rawJPEGDetector: RawJPEGPairDetector = RawJPEGPairDetector(),
        repository: DuplicateRepositoryProtocol = DuplicateRepositoryCoreData(),
        incrementalIndex: (any IncrementalIndexProtocol)? = nil
    ) {
        self.fileWalker = fileWalker
        self.byteDetector = byteDetector
        self.cloneDetector = cloneDetector
        self.dirDedupDetector = dirDedupDetector
        self.perceptualDetector = perceptualDetector
        self.largeFileDetector = largeFileDetector
        self.buildArtifactDetector = buildArtifactDetector
        self.rawJPEGDetector = rawJPEGDetector
        self.repository = repository
        self.incrementalIndex = incrementalIndex
    }

    /// Runs a full scan and streams progress, per-group results, warnings, and a
    /// final summary. Results are carried by the stream so the UI can render
    /// incrementally instead of waiting for the whole scan to finish.
    public func run(config: ProfileConfig, controller: ScanController) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            Task {
                let startDate = Date()
                do {
                let target = ScanTarget(
                    directories: config.type.scanningDirectories + config.customDirectories,
                    exclusions: config.type.additionalExclusions + config.exclusions,
                    minFileSize: config.minFileSize
                )

                // Load the incremental index (paid users only) before enumerating.
                try? await incrementalIndex?.prepare()

                // Phase 1: Enumerate (progress throttled to every N files).
                continuation.yield(.progress(ScanProgress(
                    phase: .enumerating, progress: 0, filesScanned: 0, duplicatesFound: 0
                )))
                let counter = EnumerationCounter()
                let allURLs = try await fileWalker.walk(target: target, controller: controller) { result in
                    let scanned = counter.increment()
                    if scanned % self.enumerationProgressInterval == 0 {
                        continuation.yield(.progress(ScanProgress(
                            phase: .enumerating,
                            progress: 0.15,
                            filesScanned: scanned,
                            duplicatesFound: 0,
                            currentPath: result.url.path
                        )))
                    }
                }

                guard !controller.isCancelled else { continuation.finish(); return }

                // Single metadata pass shared by the detectors that only need
                // size/type/date. Byte-identical and directory-dedup run their own
                // 4-stage verification on raw URLs.
                let fileItems = allURLs.compactMap(FileItem.fromMetadata)
                let bytesScanned = fileItems.reduce(Int64(0)) { partial, item in
                    let sum = partial.addingReportingOverflow(item.size)
                    return sum.overflow ? Int64.max : sum.partialValue
                }

                // Phase 2: Byte-identical + APFS clone annotation.
                continuation.yield(.progress(ScanProgress(
                    phase: .byteIdentical, progress: 0.2, filesScanned: allURLs.count, duplicatesFound: 0
                )))
                let indexCache = await incrementalIndex?.cachedVerifications(for: allURLs) ?? [:]
                let byteGroups = await byteDetector.detect(allURLs, controller: controller, cache: indexCache)
                let identicalGroups = await cloneDetector.annotate(byteGroups)
                let identicalCount = identicalGroups.reduce(0) { $0 + $1.files.count }
                for group in identicalGroups {
                    continuation.yield(.group(duplicateGroup: group))
                }
                for failure in await byteDetector.failures {
                    continuation.yield(.warning(ScanWarning(
                        url: failure.url, message: failure.reason, phase: .byteIdentical
                    )))
                }

                // Phase 3-7 fan out. After byteIdentical finishes, the remaining
                // detectors are independent of each other and of byteIdentical
                // (directoryDedup only needs the verifiedCache it already
                // produced). Run them concurrently on the cooperative thread
                // pool so an 8-core Mac overlaps an I/O-bound hash pass
                // (directoryDedup) with a CPU-bound perceptual pass instead of
                // serializing them. Expected wall-clock improvement on big
                // image libraries: 1.6-2.5x over the previous sequential run.
                let verifiedCache = await byteDetector.verifiedCache
                let scanRoots = target.directories.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }

                continuation.yield(.progress(ScanProgress(
                    phase: .directoryDedup,
                    progress: 0.4,
                    filesScanned: allURLs.count,
                    duplicatesFound: identicalCount
                )))
                if config.enablePerceptualScan {
                    continuation.yield(.progress(ScanProgress(
                        phase: .perceptual,
                        progress: 0.4,
                        filesScanned: allURLs.count,
                        duplicatesFound: identicalCount
                    )))
                }
                continuation.yield(.progress(ScanProgress(
                    phase: .largeFiles,
                    progress: 0.4,
                    filesScanned: allURLs.count,
                    duplicatesFound: identicalCount
                )))
                if config.enableBuildArtifacts {
                    continuation.yield(.progress(ScanProgress(
                        phase: .buildArtifacts,
                        progress: 0.4,
                        filesScanned: allURLs.count,
                        duplicatesFound: identicalCount
                    )))
                }
                continuation.yield(.progress(ScanProgress(
                    phase: .rawJPEG,
                    progress: 0.4,
                    filesScanned: allURLs.count,
                    duplicatesFound: identicalCount
                )))

                async let dedupGroups: [DuplicateGroup] = dirDedupDetector.detect(
                    allURLs,
                    roots: scanRoots,
                    controller: controller,
                    verifiedCache: verifiedCache
                )
                async let perceptualGroups: [DuplicateGroup] = config.enablePerceptualScan
                    ? perceptualDetector.detect(files: fileItems, controller: controller)
                    : []
                async let largeFiles: [FileItem] = largeFileDetector.detect(files: fileItems, controller: controller)
                async let buildGroups: [DuplicateGroup] = config.enableBuildArtifacts
                    ? buildArtifactDetector.detect(files: fileItems, controller: controller)
                    : []
                async let rawJPEGGroups: [DuplicateGroup] = rawJPEGDetector.detect(files: fileItems, controller: controller)

                // Await in dependency-friendly order; each `await` resolves
                // immediately if the underlying task already finished.
                let dedupResults = await dedupGroups
                let perceptualResults = await perceptualGroups
                let largeFileResults = await largeFiles
                let buildResults = await buildGroups
                let rawJPEGResults = await rawJPEGGroups

                let dedupCount = dedupResults.reduce(0) { $0 + $1.files.count }
                for group in dedupResults {
                    continuation.yield(.group(duplicateGroup: group))
                }
                for group in perceptualResults {
                    continuation.yield(.group(duplicateGroup: group))
                }
                continuation.yield(.largeFiles(largeFileResults))
                let largeFileBytes = largeFileResults.reduce(Int64(0)) { partial, item in
                    let sum = partial.addingReportingOverflow(item.size)
                    return sum.overflow ? Int64.max : sum.partialValue
                }
                for group in buildResults {
                    continuation.yield(.group(duplicateGroup: group))
                }
                for group in rawJPEGResults {
                    continuation.yield(.group(duplicateGroup: group))
                }

                let allGroups = identicalGroups + dedupResults + perceptualResults + buildResults + rawJPEGResults
                let groupCounts = Dictionary(grouping: allGroups, by: \.category).mapValues(\.count)
                let totalDuplicates = allGroups.reduce(largeFileResults.count) { $0 + $1.files.count }
                let totalReclaimable = allGroups.reduce(largeFileBytes) { partial, group in
                    let sum = partial.addingReportingOverflow(group.totalSize)
                    return sum.overflow ? Int64.max : sum.partialValue
                }

                let summary = ScanSummary(
                    scanId: UUID(),
                    timestamp: Date(),
                    duration: Date().timeIntervalSince(startDate),
                    filesScanned: allURLs.count,
                    bytesScanned: bytesScanned,
                    groupsFound: allGroups.count,
                    totalReclaimable: totalReclaimable,
                    groupCounts: groupCounts
                )

                continuation.yield(.progress(ScanProgress(
                    phase: .completed,
                    progress: 1.0,
                    filesScanned: allURLs.count,
                    duplicatesFound: totalDuplicates
                )))
                continuation.yield(.completed(summary))

                // Refresh the incremental index with what this scan verified.
                let verifiedFiles = allGroups.flatMap(\.files)
                await incrementalIndex?.update(files: verifiedFiles)
                let keptPaths = Set(allURLs.map(\.path))
                await incrementalIndex?.prune(keeping: keptPaths)
                try? await incrementalIndex?.persist()
                } catch {
                    // Cancellation ends the scan quietly; other failures surface
                    // as a `.failed` event so the UI can show an error state.
                    if !isCancellation(error) {
                        continuation.yield(.failed(error.localizedDescription))
                    }
                }
                continuation.finish()
            }
        }
    }

    public func saveResults(_ groups: [DuplicateGroup], config: ProfileConfig, duration: TimeInterval, filesScanned: Int) async throws {
        let totalDuplicates = groups.reduce(0) { $0 + $1.files.count }
        let totalWaste = groups.reduce(0) { $0 + $1.totalSize }
        let record = ScanRecord(
            id: UUID(), timestamp: Date(), profileType: config.type,
            totalFilesScanned: filesScanned, totalDuplicatesFound: totalDuplicates,
            totalWasteSize: totalWaste, duration: duration, groups: groups
        )
        try await repository.saveScanRecord(record)
    }
}
