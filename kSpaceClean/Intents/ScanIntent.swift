import AppIntents
import SwiftUI

// MARK: - Scan Intent

struct ScanIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan Mac Storage"
    static let description: IntentDescription = IntentDescription(
        "Run a full scan of your Mac storage with kSpaceClean.",
        categoryName: "Scanning"
    )

    static let openAppWhenRun: Bool = true

    static var parameterSummary: some ParameterSummary {
        Summary("Scan for \(\.$scanType)")
    }

    @Parameter(title: "Scan Type", default: ScanType.quick)
    var scanType: ScanType

    enum ScanType: String, AppEnum {
        case quick
        case full

        static var typeDisplayRepresentation: TypeDisplayRepresentation = "Scan Type"
        static var caseDisplayRepresentations: [ScanType: DisplayRepresentation] = [
            .quick: "Quick Scan",
            .full: "Full Scan"
        ]
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let vm = ScanViewModel()
        vm.startScan()

        // Wait for scan to complete
        while !vm.scanDidComplete {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        return .result(value: vm.scanResults.count)
    }
}

// MARK: - Clean Cache Intent

struct CleanCacheIntent: AppIntent {
    static let title: LocalizedStringResource = "Clean System Cache"
    static let description: IntentDescription = IntentDescription(
        "Clear system caches and temporary files.",
        categoryName: "Cleaning"
    )

    static let openAppWhenRun: Bool = true

    static var parameterSummary: some ParameterSummary {
        Summary("Clean \(\.$target)")
    }

    @Parameter(title: "Target", default: CacheTarget.all)
    var target: CacheTarget

    enum CacheTarget: String, AppEnum {
        case all
        case userCache
        case systemCache

        static var typeDisplayRepresentation: TypeDisplayRepresentation = "Cache Target"
        static var caseDisplayRepresentations: [CacheTarget: DisplayRepresentation] = [
            .all: "All Cache",
            .userCache: "User Cache",
            .systemCache: "System Cache"
        ]
    }

    /// SubCategory IDs that correspond to cache-type files in the scan engine.
    private static let allCacheSubCategoryIDs: Set<Int> = [
        1,  // 系统缓存
        3,  // 应用缓存
        5,  // 音频缓存
        6,  // 视频缓存
        7,  // 其他缓存
        14, // 应用缓存(聊天)
        15, // 输入法缓存
        16, // 音乐缓存
        17, // 视频缓存
        18, // 设计工具缓存
    ]

    private static let userCacheSubCategoryIDs: Set<Int> = [
        3, 5, 6, 7, 14, 15, 16, 17, 18,
    ]

    private static let systemCacheSubCategoryIDs: Set<Int> = [1]

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        // Run a scan first to populate CoreData with cache file entries
        let scanVM = ScanViewModel()
        scanVM.startScan()
        while !scanVM.scanDidComplete {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        // Determine which sub-categories to clean based on the target parameter
        let targetIDs: Set<Int>
        switch target {
        case .all:
            targetIDs = Self.allCacheSubCategoryIDs
        case .userCache:
            targetIDs = Self.userCacheSubCategoryIDs
        case .systemCache:
            targetIDs = Self.systemCacheSubCategoryIDs
        }

        let cacheFiles = scanVM.scanResults.filter { targetIDs.contains(Int($0.subCategoryID)) }
        let urls = cacheFiles.compactMap { $0.path }.map { URL(fileURLWithPath: $0) }

        guard !urls.isEmpty else { return .result(value: 0) }

        // Move matched files to Trash via the cleanup engine
        let cleanupEngine = CleanupEngine()
        var totalFreed: Int64 = 0
        for await progress in cleanupEngine.cleanup(urls: urls, skipWarnItems: true) {
            totalFreed = progress.processedBytes
        }

        return .result(value: Int(totalFreed))
    }
}

// MARK: - Show Large Files Intent

struct ShowLargeFilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Large Files"
    static let description: IntentDescription = IntentDescription(
        "Display large files on your Mac.",
        categoryName: "Scanning"
    )

    static let openAppWhenRun: Bool = true

    @Parameter(title: "Minimum Size (MB)", default: 100)
    var minimumSize: Int

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let ctx = CoreDataStack.shared.viewContext
        ctx.refreshAllObjects()

        let fetch = FileEntry.fetchRequest()
        fetch.predicate = NSPredicate(format: "size >= %lld", Int64(minimumSize) * 1_000_000)
        fetch.sortDescriptors = [NSSortDescriptor(key: "size", ascending: false)]
        fetch.fetchLimit = 100

        var entries = (try? ctx.fetch(fetch)) ?? []

        // If no scan data exists yet, run a scan first
        if entries.isEmpty {
            let vm = ScanViewModel()
            vm.startScan()
            while !vm.scanDidComplete {
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            ctx.refreshAllObjects()
            entries = (try? ctx.fetch(fetch)) ?? []
        }

        let files = entries.compactMap { entry -> IntentFile? in
            guard let path = entry.path else { return nil }
            return IntentFile(fileURL: URL(fileURLWithPath: path))
        }
        return .result(value: files)
    }
}
