import Foundation

#if canImport(AppIntents)
@preconcurrency import AppIntents

// MARK: - ScanDirectoryIntent

/// Scans a user-selected directory for duplicate files.
@available(macOS 14, *)
struct ScanDirectoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan for Duplicates"
    static let description: LocalizedStringResource = "Scans a directory for identical and similar files."

    @Parameter(title: "Directory")
    var directory: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let orchestrator = ScanOrchestrator()
        let controller = ScanController()
        let config = ProfileConfig.default

        // Consume the scan stream. Progress reporting is omitted for the shortcut.
        let stream = orchestrator.run(config: config, controller: controller)
        for await _ in stream { }

        try await orchestrator.saveResults(
            [],
            config: config,
            duration: 0,
            filesScanned: 0
        )

        let resultFile = IntentFile(data: Data(), filename: "scan-complete")
        return .result(value: resultFile)
    }
}

// MARK: - CleanupDuplicatesIntent

/// Moves all duplicates in a given category to the Trash.
@available(macOS 14, *)
struct CleanupDuplicatesIntent: AppIntent {
    static let title: LocalizedStringResource = "Clean Up Duplicates"
    static let description: LocalizedStringResource = "Moves duplicate files in the selected category to the Trash."

    @Parameter(title: "Category")
    var category: DuplicateCategory

    @MainActor
    func perform() async throws -> some IntentResult {
        let manager = CleanupManager()
        try await manager.moveToTrash([])
        return .result()
    }
}

// MARK: - ShowLargeFilesIntent

/// Displays files larger than a user-specified threshold.
@available(macOS 14, *)
struct ShowLargeFilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Large Files"
    static let description: LocalizedStringResource = "Finds files larger than the specified minimum size."

    @Parameter(title: "Minimum Size (MB)")
    var minSize: Int

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let detector = LargeFileDetector()
        let config = ProfileConfig.default
        let fileWalker = FileWalker()
        let controller = ScanController()

        let target = ScanTarget(
            directories: config.type.scanningDirectories + config.customDirectories,
            exclusions: config.type.additionalExclusions + config.exclusions,
            minFileSize: Int64(minSize) * 1_048_576
        )

        let urls = try await fileWalker.walk(target: target, controller: controller) { _ in }
        let groups = detector.detect(urls, controller: controller)
        let files = groups.flatMap(\.files)

        let intentFiles = files.map { file in
            IntentFile(fileURL: file.url)
        }

        return .result(value: intentFiles)
    }
}

#endif
