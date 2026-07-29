import Foundation
import CoreData
import DesignSystem
import FileScanner

// MARK: - LegacyScanEngine

/// 规则驱动的扫描引擎 — 遍历 ScanRuleSet 的 8 大分类,
/// 使用 FilterEvaluator 做路径解析、过滤评估、文件枚举,
/// 通过 BatchBuffer 批量写入 Core Data。
///
/// **Legacy v2 engine** — superseded by the new `ScanEngine` (Task B4)
/// in `Features/SmartScan/Engine/ScanEngine.swift`. The new engine backs
/// `ScanOrchestrator` for the v3 4-level tree; this legacy implementation
/// remains here because `ScanViewModel` still drives it via Core Data +
/// `BatchBuffer`. Both will be unified once `ScanViewModel` is migrated
/// to consume the new engine.
@MainActor
public final class LegacyScanEngine: ObservableObject {
    @Published public private(set) var progress = ScanProgress()
    public var speedOverride: ScanSpeed?
    private let cancellationToken = CancellationToken()
    private let classifier = RuleClassifier()

    public init() {}

    /// @unchecked Sendable 跨 actor 累计器
    private final class ScanStats: @unchecked Sendable {
        var files = 0
        var bytes: Int64 = 0
    }

    /// 单分类扫描结果 — 跨 actor 传递统计
    private final class CategoryResult: @unchecked Sendable {
        let categoryID: Int
        var files: Int = 0
        var bytes: Int64 = 0
        init(categoryID: Int) { self.categoryID = categoryID }
    }

    /// ScanCategory.id → FileCategory fallback (used when RuleClassifier returns .other)
    private static func fallbackCategory(for categoryID: Int) -> FileCategory {
        switch categoryID {
        case 1, 5, 6, 8: return .cache
        case 2: return .dev
        case 3, 4, 7: return .app
        default: return .other
        }
    }

    public func startScan() async {
        let speed = speedOverride ?? UserPreferences.load().scanSpeed
        let rules = ScanRuleSet.default
        let buffer = BatchBuffer(backgroundContext: CoreDataStack.shared.backgroundContext())
        let stats = ScanStats()

        // Initialize per-category progress
        let categoryProgress = rules.categories.map { cat in
            CategoryProgress(
                id: cat.id,
                title: cat.title,
                status: .pending,
                subCategories: cat.subCategories.map { sub in
                    SubCategoryProgress(id: sub.id, title: sub.title, status: .pending)
                },
                filesFound: 0,
                totalSize: 0
            )
        }

        progress = ScanProgress(state: .scanning, speed: speed, categoryProgress: categoryProgress)

        // ── Phase 1: 8 内置分类并行扫描 ──
        await withTaskGroup(of: CategoryResult.self) { [weak self] group in
            guard let self else { return }
            for category in rules.categories {
                group.addTask {
                    let evaluator = FilterEvaluator(filters: rules.filters)
                    return await self.scanCategory(
                        category,
                        evaluator: evaluator,
                        speed: speed,
                        stats: stats,
                        buffer: buffer
                    )
                }
            }

            var completedCount = 0
            for await result in group {
                completedCount += 1
                await MainActor.run {
                    self.updateCategoryProgress(
                        id: result.categoryID,
                        status: .completed,
                        filesFound: result.files,
                        totalSize: result.bytes
                    )
                    var p = self.progress
                    p.filesDiscovered = stats.files
                    p.totalBytes = stats.bytes
                    self.progress = p
                }
                _ = completedCount
            }
            await MainActor.run {
                var p = self.progress
                p.filesDiscovered = stats.files
                p.totalBytes = stats.bytes
                self.progress = p
            }
        }

        // ── Phase 2: 已安装应用的具体规则 (22 App Rules) — 串行（轻量、依赖运行进程检测） ──
        let installedRules = AppScanRule.installedApps()
        let evaluator2 = FilterEvaluator(filters: rules.filters)
        for rule in installedRules {
            if cancellationToken.isCancelled { break }

            await scanAppRule(rule, evaluator: evaluator2, speed: speed,
                              stats: stats, buffer: buffer)
        }

        // 最终 flush
        buffer.flush()

        // Reload viewContext to ensure all newly inserted objects are visible
        CoreDataStack.shared.viewContext.refreshAllObjects()

        let isCancelled = cancellationToken.isCancelled
        progress = ScanProgress(
            state: isCancelled ? .cancelled : .completed,
            filesDiscovered: stats.files,
            totalBytes: stats.bytes,
            finishedAt: isCancelled ? nil : Date(),
            speed: speed,
            categoryProgress: progress.categoryProgress
        )
    }

    public func cancel() {
        cancellationToken.cancel()
        progress = ScanProgress(state: .cancelled)
    }

    // MARK: - Parallel Category Worker

    /// 单分类扫描 — 在 TaskGroup 子任务中运行。返回该分类累计的文件/字节统计。
    private func scanCategory(
        _ category: RuleScanCategory,
        evaluator: FilterEvaluator,
        speed: ScanSpeed,
        stats: ScanStats,
        buffer: BatchBuffer
    ) async -> CategoryResult {
        let accumulator = CategoryResult(categoryID: category.id)
        let fileCategoryFallback = Self.fallbackCategory(for: category.id)

        for subCategory in category.subCategories {
            if cancellationToken.isCancelled { return accumulator }

            for action in subCategory.actions {
                if cancellationToken.isCancelled { return accumulator }

                let specializedScanner = SpecializedScannerRegistry.defaults[action.type]

                for scanPath in action.paths {
                    if cancellationToken.isCancelled { return accumulator }

                    let urls = evaluator.resolvePath(scanPath)
                    for url in urls {
                        if cancellationToken.isCancelled { return accumulator }

                        let makeEntry: @Sendable (URL, Int64) -> ScanResultEntry? = { fileURL, fileSize in
                            if let resultFilters = action.resultFilters {
                                let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
                                let modDate = attrs?[FileAttributeKey.modificationDate] as? Date
                                guard evaluator.evaluate(resultFilters, for: fileURL, fileSize: fileSize, fileTime: modDate) else {
                                    return nil
                                }
                            }
                            let detectedCategory = self.classifier.classify(fileURL)
                            let effectiveCategory = detectedCategory != .other ? detectedCategory : fileCategoryFallback
                            return ScanResultEntry(
                                path: fileURL.path,
                                size: fileSize,
                                category: effectiveCategory.rawValue,
                                subCategoryID: subCategory.id,
                                actionID: action.actionID,
                                isTruncatable: action.type == .file,
                                isRecommended: action.recommended
                            )
                        }

                        do {
                            if let scanner = specializedScanner {
                                try await scanner.scan(
                                    url: url,
                                    level: scanPath.level,
                                    speed: speed,
                                    cancellationToken: cancellationToken,
                                    onFile: { fileURL, fileSize in
                                        if let entry = makeEntry(fileURL, fileSize) {
                                            buffer.append(entry)
                                            accumulator.files += 1
                                            accumulator.bytes += fileSize
                                        }
                                    }
                                )
                            } else {
                                try await evaluator.enumerateFiles(
                                    at: url,
                                    level: scanPath.level,
                                    filenamePattern: scanPath.filenamePattern,
                                    scanFilters: scanPath.scanFilters,
                                    cleanHiddenFiles: action.cleanHiddenFiles,
                                    speed: speed,
                                    cancellationToken: cancellationToken,
                                    onFile: { fileURL, fileSize in
                                        if let entry = makeEntry(fileURL, fileSize) {
                                            buffer.append(entry)
                                            accumulator.files += 1
                                            accumulator.bytes += fileSize
                                        }
                                    }
                                )
                            }
                        } catch {
                            continue
                        }
                    }
                }
            }
        }

        // 累计到共享 stats
        stats.files += accumulator.files
        stats.bytes += accumulator.bytes
        return accumulator
    }

    /// 扫描单条已安装 App 规则 — 不参与并行（依赖 NSWorkspace.runningApplications）。
    private func scanAppRule(
        _ rule: AppScanRule,
        evaluator: FilterEvaluator,
        speed: ScanSpeed,
        stats: ScanStats,
        buffer: BatchBuffer
    ) async {
        let appCategoryFallback = Self.fallbackCategory(for: rule.categoryID)

        for action in rule.actions {
            if cancellationToken.isCancelled { break }

            for pattern in action.paths {
                if cancellationToken.isCancelled { break }

                let expandedPath = (pattern as NSString).expandingTildeInPath
                let url = URL(fileURLWithPath: expandedPath)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }

                do {
                    try await evaluator.enumerateFiles(
                        at: url,
                        level: action.level,
                        filenamePattern: nil,
                        scanFilters: nil,
                        cleanHiddenFiles: false,
                        speed: speed,
                        cancellationToken: cancellationToken,
                        onFile: { fileURL, fileSize in
                            if action.requireTimeFilter {
                                let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
                                if let modDate = attrs?[.modificationDate] as? Date,
                                   modDate > Date().addingTimeInterval(-30 * 86400) {
                                    return
                                }
                            }
                            let detectedCategory = self.classifier.classify(fileURL)
                            let effectiveCategory = detectedCategory != .other ? detectedCategory : appCategoryFallback
                            let entry = ScanResultEntry(
                                path: fileURL.path,
                                size: fileSize,
                                category: effectiveCategory.rawValue,
                                subCategoryID: rule.subCategoryID,
                                actionID: action.actionID,
                                isRecommended: action.recommended
                            )
                            buffer.append(entry)
                            stats.files += 1
                            stats.bytes += fileSize
                        }
                    )
                } catch {
                    continue
                }
            }
        }
    }

    // MARK: - Progress Tracking Helpers

    private func updateCategoryStatus(id: Int, status: ScanItemStatus) {
        var p = progress
        var catProgress = p.categoryProgress
        if let idx = catProgress.firstIndex(where: { $0.id == id }) {
            var cp = catProgress[idx]
            cp.status = status
            catProgress[idx] = cp
        }
        p.categoryProgress = catProgress
        progress = p
    }

    private func updateSubCategoryStatus(categoryID: Int, subID: Int, status: ScanItemStatus) {
        var p = progress
        var catProgress = p.categoryProgress
        if let catIdx = catProgress.firstIndex(where: { $0.id == categoryID }) {
            var cp = catProgress[catIdx]
            if let subIdx = cp.subCategories.firstIndex(where: { $0.id == subID }) {
                var sp = cp.subCategories[subIdx]
                sp.status = status
                cp.subCategories[subIdx] = sp
            }
            catProgress[catIdx] = cp
        }
        p.categoryProgress = catProgress
        progress = p
    }

    private func updateCategoryProgress(id: Int, status: ScanItemStatus, filesFound: Int, totalSize: Int64) {
        var p = progress
        var catProgress = p.categoryProgress
        if let idx = catProgress.firstIndex(where: { $0.id == id }) {
            var cp = catProgress[idx]
            cp.status = status
            cp.filesFound = filesFound
            cp.totalSize = totalSize
            catProgress[idx] = cp
        }
        p.categoryProgress = catProgress
        progress = p
    }
}
