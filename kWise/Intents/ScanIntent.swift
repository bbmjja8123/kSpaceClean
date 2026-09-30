import AppIntents
import SwiftUI

// MARK: - Scan Intent
//
// P1 T9 — 双引擎退役：三个 AppIntents 全部改走 `IntentScanAdapter`
// （v3 `ScanOrchestrator` 链）。旧规则引擎 + Core Data 管线与
// 硬编码 `Set<Int>` subCategoryID 映射已删除（R4）。

struct ScanIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan Mac Storage"
    static let description: IntentDescription = IntentDescription(
        "Run a full scan of your Mac storage with kWise.",
        categoryName: "Scanning"
    )

    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let summary = await IntentScanAdapter.scanSummary(scope: AppScope.shared)
        return .result(value: summary.categories)
    }
}

// MARK: - Clean Cache Intent
//
// 语义（诚实化）：不再按硬编码 subCategoryID 过滤——改为跑一次新扫描后
// 收敛「推荐级（可安全默认勾选）」的叶子，交给 `CleanupEngine.cleanup
// (targets:)` 移入废纸篓（历史/回滚/事件 sink 全部走引擎）。

struct CleanCacheIntent: AppIntent {
    static let title: LocalizedStringResource = "Clean System Cache"
    static let description: IntentDescription = IntentDescription(
        "Scan for safe-to-clean files and move them to the Trash.",
        categoryName: "Cleaning"
    )

    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let (targets, _) = await IntentScanAdapter.recommendedPickTargets(scope: AppScope.shared)
        guard !targets.isEmpty else { return .result(value: 0) }

        // Shared process-wide graph engine so history, the menu-bar
        // "最近清理" row, and the other event sinks stay in sync.
        let engine = AppGraph.shared.cleanupEngine
        let outcome = try await engine.cleanup(targets: targets)
        return .result(value: Int(outcome.freedBytes))
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
        let threshold = Int64(minimumSize) * 1_000_000
        let results = await IntentScanAdapter.largestFiles(scope: AppScope.shared, limit: 100)
        let files = results
            .filter { $0.fileSize >= threshold }
            .map { IntentFile(fileURL: $0.url) }
        return .result(value: files)
    }
}
