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

                // Phase 3: Directory dedup.
                continuation.yield(.progress(ScanProgress(
                    phase: .directoryDedup,
                    progress: 0.4,
                    filesScanned: allURLs.count,
                    duplicatesFound: identicalCount
                )))
                let scanRoots = target.directories.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                let dedupGroups = await dirDedupDetector.detect(
                    allURLs,
                    roots: scanRoots,
                    controller: controller
                )
                let dedupCount = dedupGroups.reduce(0) { $0 + $1.files.count }
                for group in dedupGroups {
                    continuation.yield(.group(duplicateGroup: group))
                }

                // Phase 4: Perceptual (honor config flag).
                var perceptualGroups: [DuplicateGroup] = []
                if config.enablePerceptualScan {
                    continuation.yield(.progress(ScanProgress(
                        phase: .perceptual,
                        progress: 0.6,
                        filesScanned: allURLs.count,
                        duplicatesFound: identicalCount + dedupCount
                    )))
                    perceptualGroups = await perceptualDetector.detect(files: fileItems, controller: controller)
                    for group in perceptualGroups {
                        continuation.yield(.group(duplicateGroup: group))
                    }
                }

                // Phase 5: Large files (flat list, streamed as a single event).
                continuation.yield(.progress(ScanProgress(
                    phase: .largeFiles,
                    progress: 0.75,
                    filesScanned: allURLs.count,
                    duplicatesFound: identicalCount + dedupCount
                )))
                let largeFiles = await largeFileDetector.detect(files: fileItems, controller: controller)
                continuation.yield(.largeFiles(largeFiles))
                let largeFileBytes = largeFiles.reduce(Int64(0)) { partial, item in
                    let sum = partial.addingReportingOverflow(item.size)
                    return sum.overflow ? Int64.max : sum.partialValue
                }

                // Phase 6: Build artifacts. Honors the settings toggle so users
                // who only want byte-identical / perceptual / RAW+JPEG matches
                // can skip this pass entirely.
                var buildGroups: [DuplicateGroup] = []
                if config.enableBuildArtifacts {
                    continuation.yield(.progress(ScanProgress(
                        phase: .buildArtifacts,
                        progress: 0.85,
                        filesScanned: allURLs.count,
                        duplicatesFound: identicalCount + dedupCount + largeFiles.count
                    )))
                    buildGroups = await buildArtifactDetector.detect(files: fileItems, controller: controller)
                    for group in buildGroups {
                        continuation.yield(.group(duplicateGroup: group))
                    }
                }

                // Phase 7: RAW + JPEG pairs.
                continuation.yield(.progress(ScanProgress(
                    phase: .rawJPEG,
                    progress: 0.95,
                    filesScanned: allURLs.count,
                    duplicatesFound: identicalCount + dedupCount + largeFiles.count + buildGroups.count
                )))
                let rawJPEGGroups = await rawJPEGDetector.detect(files: fileItems, controller: controller)
                for group in rawJPEGGroups {
                    continuation.yield(.group(duplicateGroup: group))
                }

                let allGroups = identicalGroups + dedupGroups + perceptualGroups + buildGroups + rawJPEGGroups
                let groupCounts = Dictionary(grouping: allGroups, by: \.category).mapValues(\.count)
                let totalDuplicates = allGroups.reduce(largeFiles.count) { $0 + $1.files.count }
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
