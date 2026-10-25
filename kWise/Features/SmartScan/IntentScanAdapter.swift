// kWise/Features/SmartScan/IntentScanAdapter.swift
//
// P1 T9 — 双引擎退役。AppIntents（ScanIntent / CleanCacheIntent /
// ShowLargeFilesIntent）不再驱动旧规则引擎 + Core Data 管线，
// 全部改走 v3 `ScanOrchestrator` 链。本 adapter 是 Intents 与扫描引擎
// 之间的唯一契约层。
//
// C4 红线：推荐挑选只收敛 `riskLevel.defaultChecked`（即 `.recommended`）
// 的叶子——危险项绝不进入 Intents 的自动清理集。挑选遍历与 Smart Care
// 共享单源（SmartCareOrchestrator 复用 `recommendedEntries`）。

import Foundation
import CommonUtils

enum IntentScanAdapter {

    // MARK: - Shared recommended-pick traversal (single source)

    /// 四层遍历（category → sub → action → result），收集每个 risk 等级
    /// 可默认勾选（`.recommended`）的叶子。
    ///
    /// 判定基准是 `riskLevel.defaultChecked` 而非旧 `isRecommended` 标志：
    /// 标志沿用自旧规则集时代，可能与 risk 等级不一致（例如危险文件挂着
    /// 推荐 flag）。以 risk 等级为准是 C4 红线在 Intents 链路上的执行点。
    static func recommendedEntries(in categories: [ScanCategory]) -> [ScanResult] {
        var picks: [ScanResult] = []
        for category in categories {
            for sub in category.subItems {
                for action in sub.actions {
                    for entry in action.results where entry.riskLevel.defaultChecked {
                        picks.append(entry)
                    }
                }
            }
        }
        return picks
    }

    /// 把推荐叶子收敛成 `CleanupTarget`（C4：risk 恒 `.recommended`，
    /// size 取扫描时字节数——history 行与 freedBytes 依赖这两个字段）。
    static func targetsFromRecommendedPicks(in categories: [ScanCategory]) -> [CleanupTarget] {
        recommendedEntries(in: categories).map { entry in
            CleanupTarget(url: entry.url, size: entry.fileSize, risk: .recommended)
        }
    }

    // MARK: - Intent entry points

    /// CleanCacheIntent：跑一次新扫描 → 收敛推荐项。清理本身由 intent
    /// 调 `CleanupEngine.cleanup(targets:)` 完成（历史/回滚/sink 走引擎）。
    /// 不做任何静默 subCategoryID 映射——旧 `Set<Int>` 语义已废除（R4）。
    @MainActor
    static func recommendedPickTargets(scope: AppScope) async -> (targets: [CleanupTarget], summary: String) {
        let categories = await scanCategories(scope: scope)
        let targets = targetsFromRecommendedPicks(in: categories)
        let bytes = targets.reduce(Int64(0)) { $0 + $1.size }
        let summary = String(
            format: String(localized: String.LocalizationValue("intents.summary.recommendedPicks")),
            Int64(targets.count), FileSizeFormatter.abbreviated(from: bytes))
        return (targets, summary)
    }

    /// ShowLargeFilesIntent：扫描后按大小降序取前 `limit` 个叶子
    /// （覆盖 app 桶的 action 结果与 pseudo-app 桶的 direct 结果）。
    /// 仅展示用——不筛 risk，不触发清理。
    @MainActor
    static func largestFiles(scope: AppScope, limit: Int) async -> [ScanResult] {
        let categories = await scanCategories(scope: scope)
        let leaves = categories.flatMap { category in
            category.subItems.flatMap { sub in
                sub.actions.flatMap { $0.results } + sub.directResults
            }
        }
        return Array(leaves.sorted { $0.fileSize > $1.fileSize }.prefix(limit))
    }

    /// ScanIntent：一次扫描后的（分类数, 字节数）摘要。
    @MainActor
    static func scanSummary(scope: AppScope) async -> (categories: Int, bytes: Int64) {
        let categories = await scanCategories(scope: scope)
        return (categories.count, categories.reduce(Int64(0)) { $0 + $1.totalSize })
    }

    // MARK: - Scan driver

    /// 跑一次完整扫描并返回终态分类树。`ScanOrchestrator` 是单次实例
    /// （见其 Lifecycle 注释），每次调用新建 orchestrator + engine。
    /// 完成判定走 `ScanEngine.waitForScanCompletion()`（确定性完成，
    /// 由 ScanEngineIntegrationTests 钉死的行为）。
    @MainActor
    private static func scanCategories(scope: AppScope) async -> [ScanCategory] {
        let engine = ScanEngine(orchestrator: ScanOrchestrator(scope: scope.scope))
        await engine.startScan()
        await engine.waitForScanCompletion()
        return engine.categories
    }
}
