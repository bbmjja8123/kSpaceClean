import Foundation
import FileScanner

public actor ScanOrchestrator {
    private let fileWalker: FileWalker
    private let byteDetector: ByteIdenticalDetector
    private let dirDedupDetector: DirectoryDedupDetector
    private let perceptualDetector: PerceptualDetector
    private let largeFileDetector: LargeFileDetector
    private let buildArtifactDetector: BuildArtifactDetector
    private let rawJPEGDetector: RawJPEGPairDetector
    private let repository: DuplicateRepositoryProtocol

    public init(
        fileWalker: FileWalker = FileWalker(),
        byteDetector: ByteIdenticalDetector = ByteIdenticalDetector(),
        dirDedupDetector: DirectoryDedupDetector = DirectoryDedupDetector(),
        perceptualDetector: PerceptualDetector = PerceptualDetector(),
        largeFileDetector: LargeFileDetector = LargeFileDetector(),
        buildArtifactDetector: BuildArtifactDetector = BuildArtifactDetector(),
        rawJPEGDetector: RawJPEGPairDetector = RawJPEGPairDetector(),
        repository: DuplicateRepositoryProtocol = DuplicateRepositoryCoreData()
    ) {
        self.fileWalker = fileWalker
        self.byteDetector = byteDetector
        self.dirDedupDetector = dirDedupDetector
        self.perceptualDetector = perceptualDetector
        self.largeFileDetector = largeFileDetector
        self.buildArtifactDetector = buildArtifactDetector
        self.rawJPEGDetector = rawJPEGDetector
        self.repository = repository
    }

    public func run(config: ProfileConfig, controller: ScanController) -> AsyncStream<ScanProgress> {
        AsyncStream { continuation in
            Task {
                let target = ScanTarget(
                    directories: config.type.scanningDirectories + config.customDirectories,
                    exclusions: config.type.additionalExclusions + config.exclusions,
                    minFileSize: config.minFileSize
                )

                // Phase 1: Enumerate
                continuation.yield(ScanProgress(phase: .enumerating, progress: 0, filesScanned: 0, duplicatesFound: 0))
                let allURLs = try await fileWalker.walk(target: target, controller: controller) { result in
                    // progress callback
                }

                guard !controller.isCancelled else { continuation.finish(); return }
                continuation.yield(ScanProgress(phase: .byteIdentical, progress: 0.2, filesScanned: allURLs.count, duplicatesFound: 0))

                // Phase 2: Byte-identical
                let identicalGroups = try await byteDetector.detect(allURLs, controller: controller)
                let identicalCount = identicalGroups.reduce(0) { $0 + $1.files.count }

                // Phase 3: Directory dedup
                continuation.yield(ScanProgress(phase: .directoryDedup, progress: 0.4, filesScanned: allURLs.count, duplicatesFound: identicalCount))
                let dedupGroups = try await dirDedupDetector.detect(allURLs, controller: controller)
                let dedupCount = dedupGroups.reduce(0) { $0 + $1.files.count }

                // Phase 4: Perceptual
                continuation.yield(ScanProgress(phase: .perceptual, progress: 0.6, filesScanned: allURLs.count, duplicatesFound: identicalCount + dedupCount))
                let perceptualGroups = try await perceptualDetector.detect(allURLs, controller: controller)
                let perceptualCount = perceptualGroups.reduce(0) { $0 + $1.files.count }

                // Phase 5: Large files
                continuation.yield(ScanProgress(phase: .largeFiles, progress: 0.8, filesScanned: allURLs.count, duplicatesFound: identicalCount + dedupCount + perceptualCount))
                let largeGroups = largeFileDetector.detect(allURLs, controller: controller)

                // Phase 6: Build artifacts
                continuation.yield(ScanProgress(phase: .buildArtifacts, progress: 0.9, filesScanned: allURLs.count, duplicatesFound: identicalCount + dedupCount + perceptualCount + largeGroups.count))
                let buildGroups = buildArtifactDetector.detect(allURLs, controller: controller)

                // Phase 7: RAW+JPEG
                continuation.yield(ScanProgress(phase: .rawJPEG, progress: 0.95, filesScanned: allURLs.count, duplicatesFound: identicalCount + dedupCount + perceptualCount + largeGroups.count + buildGroups.count))
                let rawJPEGGroups = await rawJPEGDetector.detect(allURLs, controller: controller)

                // Combine
                let allGroups = identicalGroups + dedupGroups + perceptualGroups + largeGroups + buildGroups + rawJPEGGroups
                let totalDuplicates = allGroups.reduce(0) { $0 + $1.files.count }
                let totalWaste = allGroups.reduce(0) { $0 + $1.totalSize }

                continuation.yield(ScanProgress(phase: .completed, progress: 1.0, filesScanned: allURLs.count, duplicatesFound: totalDuplicates))
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
