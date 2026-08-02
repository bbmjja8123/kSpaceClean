import Foundation

#if canImport(AppIntents)
@preconcurrency import AppIntents

// MARK: - Shared keys (App Group)

/// Keys used to ferry the Finder-Sync → main-app handoff through the shared
/// App Group UserDefaults. Keep the prefix in sync with the main app.
private enum FinderSyncKeys {
    static let pendingPath = "ksift.finderSync.pendingPath"
}

// MARK: - ScanDirectoryIntent

/// Scans a user-selected directory for duplicate files and surfaces the
/// results in the app. The directory parameter is honored — previous
/// versions silently scanned the default profile dirs and dropped the
/// user's choice on the floor.
@available(macOS 14, *)
struct ScanDirectoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan for Duplicates"
    static let description: LocalizedStringResource = "Scans a directory for identical and similar files."
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Directory")
    var directory: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let dirURL = directory.fileURL ?? URL(fileURLWithPath: NSHomeDirectory())
        let base = ProfileConfigStore.load()
        // Honor the user's directory while keeping their configured
        // exclusions/min-size/perceptual/build-artifact preferences.
        let config = ProfileConfig(
            type: base.type,
            customDirectories: [dirURL.path],
            exclusions: base.exclusions,
            minFileSize: base.minFileSize,
            enablePerceptualScan: base.enablePerceptualScan,
            enableBuildArtifacts: base.enableBuildArtifacts
        )

        let orchestrator = ScanOrchestrator()
        let controller = ScanController()
        let start = Date()
        let stream = await orchestrator.run(config: config, controller: controller)
        var collected: [DuplicateGroup] = []
        for await event in stream {
            if case .group(let group) = event {
                collected.append(group)
            }
        }

        try await orchestrator.saveResults(
            collected,
            config: config,
            duration: Date().timeIntervalSince(start),
            filesScanned: 0
        )

        // Hand off to the main app so the result screen can pick it up.
        Self.appState?.latestGroups = collected
        Self.appState?.navigation = .results

        return .result(value: collected.count)
    }

    /// Set by the app at launch so intents running in the app process can
    /// publish results into the same AppState the UI observes.
    @MainActor static var appState: AppState?
}

// MARK: - CleanupDuplicatesIntent

/// Moves duplicates in a chosen category to the Trash. Operates on the most
/// recent persisted scan record — the intent must have something to act on,
/// so it requires a prior scan (which `ScanDirectoryIntent` or the app UI
/// will have produced).
@available(macOS 14, *)
struct CleanupDuplicatesIntent: AppIntent {
    static let title: LocalizedStringResource = "Clean Up Duplicates"
    static let description: LocalizedStringResource = "Moves duplicate files in the selected category to the Trash."
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Category")
    var category: DuplicateCategory

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let repository = DuplicateRepositoryCoreData()
        guard let record = try await repository.loadScanRecords().first else {
            return .result(value: 0)
        }
        let matchingFiles = Self.filesToDelete(in: record.groups, category: category)

        let manager = CleanupManager()
        let result = try await manager.moveToTrash(matchingFiles, profileType: category.rawValue)
        return .result(value: matchingFiles.count - result.failures.count)
    }

    /// Per group, keep the newest file and move the rest. Matches the
    /// keep-newest semantics used by the in-app result screen.
    static func filesToDelete(in groups: [DuplicateGroup], category: DuplicateCategory) -> [FileItem] {
        groups
            .filter { $0.category == category && $0.files.count > 1 }
            .flatMap { group -> [FileItem] in
                let sorted = group.files.sorted { $0.modificationDate > $1.modificationDate }
                return Array(sorted.dropFirst())
            }
    }
}

// MARK: - ShowLargeFilesIntent

/// Displays files larger than a user-specified threshold using the user's
/// configured scan directories (not the hardcoded default).
@available(macOS 14, *)
struct ShowLargeFilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Large Files"
    static let description: LocalizedStringResource = "Finds files larger than the specified minimum size."
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Minimum Size (MB)")
    var minSize: Int

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let detector = LargeFileDetector()
        let config = ProfileConfigStore.load()
        let fileWalker = FileWalker()
        let controller = ScanController()

        let target = ScanTarget(
            directories: config.type.scanningDirectories + config.customDirectories,
            exclusions: config.type.additionalExclusions + config.exclusions,
            minFileSize: Int64(minSize) * 1_048_576
        )

        let urls = try await fileWalker.walk(target: target, controller: controller) { _ in }
        let files = await detector.detect(urls, controller: controller)

        let intentFiles = files.map { IntentFile(fileURL: $0.url) }
        return .result(value: intentFiles)
    }
}

#endif