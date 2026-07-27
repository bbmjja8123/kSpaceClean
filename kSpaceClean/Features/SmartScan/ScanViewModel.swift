import Foundation
import SwiftUI
import Combine
import DesignSystem

@MainActor
public final class ScanViewModel: ObservableObject {
    @Published public var progress = ScanProgress()
    @Published public var scanResults: [FileEntry] = []
    @Published public var resultGroups: [ScanResultGroup] = []
    /// Fires AFTER scanResults are populated — RootView observes this instead of progress.state to avoid timing races
    @Published public var scanDidComplete = false
    private let engine = ScanEngine()
    private var cancellables = Set<AnyCancellable>()
    private let classifier = RuleClassifier()

    // MARK: - SubCategory metadata

    private static let actionIDToTitle: [Int: String] = {
        var map: [Int: String] = [:]
        for rule in AppScanRule.allApps {
            for action in rule.actions {
                map[action.actionID] = action.title
            }
        }
        return map
    }()

    private static let subCategoryTitles: [Int: String] = [
        1: "系统缓存", 2: "系统日志", 3: "应用缓存", 4: "应用残留",
        5: "音频缓存", 6: "视频缓存", 7: "其他缓存",
        14: "应用缓存(聊天)", 15: "输入法缓存", 16: "音乐缓存",
        17: "视频缓存", 18: "设计工具缓存", 51: "Xcode 残留",
    ]

    private static let actionIDToAppName: [Int: String] = {
        var map: [Int: String] = [:]
        for rule in AppScanRule.allApps {
            for action in rule.actions {
                map[action.actionID] = rule.appName
            }
        }
        return map
    }()

    private static let actionIDToCaution: [Int: Int] = {
        var map: [Int: Int] = [:]
        for rule in AppScanRule.allApps {
            for action in rule.actions {
                if let cid = action.cautionID, cid != 0 {
                    map[action.actionID] = cid
                }
            }
        }
        return map
    }()

    public init() {
        // Observe engine progress changes
        engine.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newProgress in
                self?.progress = newProgress
            }
            .store(in: &cancellables)

        // Progressive delivery — each BatchBuffer flush fires this notification.
        // We re-fetch incrementally so results appear before the full scan finishes.
        NotificationCenter.default
            .publisher(for: .init("ScanBatchFlushed"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refetchIncremental()
            }
            .store(in: &cancellables)
    }

    /// 增量刷新结果列表 — 在 ScanBatchFlushed 通知时调用,
    /// 从 Core Data 拉取所有 FileEntry 并重建 resultGroups。
    /// 增量更新算法使用 id 去重,避免重复条目。
    private var knownEntryIDs: Set<UUID> = []
    private func refetchIncremental() {
        let ctx = CoreDataStack.shared.viewContext
        ctx.refreshAllObjects()
        let fetch = FileEntry.fetchRequest()
        fetch.sortDescriptors = [NSSortDescriptor(key: "size", ascending: false)]
        let all = (try? ctx.fetch(fetch)) ?? []

        // 增量并入 — 仅添加新 id
        var added = 0
        for entry in all {
            guard let id = entry.id else { continue }
            if knownEntryIDs.insert(id).inserted {
                added += 1
            }
        }
        if added > 0 || scanResults.isEmpty {
            scanResults = all
            resultGroups = Self.buildResultGroups(from: all)
        }
    }

    public func startScan() {
        scanResults = []
        resultGroups = []
        scanDidComplete = false
        knownEntryIDs = []
        progress = ScanProgress(state: .scanning)

        Task {
            await engine.startScan()

            // After scan completes, load ALL results from Core Data (no fetchLimit)
            let ctx = CoreDataStack.shared.viewContext
            ctx.refreshAllObjects()
            let fetch = FileEntry.fetchRequest()
            fetch.sortDescriptors = [NSSortDescriptor(key: "size", ascending: false)]
            scanResults = (try? ctx.fetch(fetch)) ?? []

            // Post-scan reclassification: fix entries with fallback-only categories
            let classifier = RuleClassifier()
            var needsSave = false
            for entry in scanResults {
                guard let path = entry.path else { continue }
                let url = URL(fileURLWithPath: path)
                let detected = classifier.classify(url)
                let entryCategory = entry.category ?? ""
                // Reclassify if classifier detects a specific category different from stored one
                if detected != .other && entryCategory != detected.rawValue {
                    entry.category = detected.rawValue
                    needsSave = true
                }
            }
            if needsSave {
                try? ctx.save()
            }

            // Build result groups for expandable tree UI
            resultGroups = Self.buildResultGroups(from: scanResults)

            // Apply default selection based on risk levels
            applyDefaultSelection()

            // Signal completion AFTER results are populated
            scanDidComplete = true
        }
    }

    public func cancelScan() {
        engine.cancel()
    }

    // MARK: - Selection Management

    public func toggleItem(_ id: UUID) {
        var updated = resultGroups
        for gi in updated.indices {
            // Flat items (legacy)
            if let ii = updated[gi].items.firstIndex(where: { $0.id == id }) {
                updated[gi].items[ii].isSelected.toggle()
                resultGroups = updated
                return
            }
            // Nested items in action groups
            for ai in updated[gi].actionGroups.indices {
                if let ii = updated[gi].actionGroups[ai].items.firstIndex(where: { $0.id == id }) {
                    updated[gi].actionGroups[ai].items[ii].isSelected.toggle()
                    resultGroups = updated
                    return
                }
            }
        }
    }

    public func toggleGroup(_ subID: Int) {
        guard let gi = resultGroups.firstIndex(where: { $0.id == subID }) else { return }
        let allItems = resultGroups[gi].actionGroups.isEmpty
            ? resultGroups[gi].items
            : resultGroups[gi].actionGroups.flatMap { $0.items }
        let newValue = !allItems.allSatisfy(\.isSelected)
        if resultGroups[gi].actionGroups.isEmpty {
            for ii in resultGroups[gi].items.indices {
                resultGroups[gi].items[ii].isSelected = newValue
            }
        } else {
            for ai in resultGroups[gi].actionGroups.indices {
                for ii in resultGroups[gi].actionGroups[ai].items.indices {
                    resultGroups[gi].actionGroups[ai].items[ii].isSelected = newValue
                }
            }
        }
        let copy = resultGroups
        resultGroups = copy
    }

    public func toggleActionGroup(_ actionID: Int) {
        for gi in resultGroups.indices {
            if let ai = resultGroups[gi].actionGroups.firstIndex(where: { $0.id == actionID }) {
                let newValue = !resultGroups[gi].actionGroups[ai].isAllSelected
                for ii in resultGroups[gi].actionGroups[ai].items.indices {
                    resultGroups[gi].actionGroups[ai].items[ii].isSelected = newValue
                }
                let copy = resultGroups
                resultGroups = copy
                return
            }
        }
    }

    public func toggleActionExpanded(_ actionID: Int) {
        for gi in resultGroups.indices {
            if let ai = resultGroups[gi].actionGroups.firstIndex(where: { $0.id == actionID }) {
                resultGroups[gi].actionGroups[ai].isExpanded.toggle()
                let copy = resultGroups
                resultGroups = copy
                return
            }
        }
    }

    public var selectedCount: Int {
        resultGroups.reduce(0) { acc, group in
            acc + (group.actionGroups.isEmpty
                   ? group.items.filter(\.isSelected).count
                   : group.actionGroups.reduce(0) { $0 + $1.items.filter(\.isSelected).count })
        }
    }

    public var selectedSize: Int64 {
        resultGroups.reduce(0) { $0 + $1.selectedSize }
    }

    // MARK: - Risk-Grouped Stats

    public struct RiskGroupedStats: Sendable {
        public let recommended: (count: Int, size: Int64)
        public let optional: (count: Int, size: Int64)
        public let caution: (count: Int, size: Int64)
        public let dangerous: (count: Int, size: Int64)
        public let totalCount: Int
        public let totalSize: Int64
        public let selectedSize: Int64
    }

    public var riskGroupedStats: RiskGroupedStats {
        var rec = (0, Int64(0))
        var opt = (0, Int64(0))
        var cau = (0, Int64(0))
        var dan = (0, Int64(0))
        var totalSel = Int64(0)
        for group in resultGroups {
            for ag in group.actionGroups {
                for item in ag.items {
                    switch item.riskLevel {
                    case .recommended: rec.0 += 1; rec.1 += item.size
                    case .optional: opt.0 += 1; opt.1 += item.size
                    case .caution: cau.0 += 1; cau.1 += item.size
                    case .dangerous: dan.0 += 1; dan.1 += item.size
                    }
                    if item.isSelected { totalSel += item.size }
                }
            }
        }
        return RiskGroupedStats(
            recommended: rec, optional: opt, caution: cau, dangerous: dan,
            totalCount: rec.0 + opt.0 + cau.0 + dan.0,
            totalSize: rec.1 + opt.1 + cau.1 + dan.1,
            selectedSize: totalSel
        )
    }

    // MARK: - Default Selection

    public func applyDefaultSelection(policy: RecommendPolicy = .default) {
        let selector = DefaultSelectionPolicy(policy: policy)
        var updated = resultGroups
        for gi in updated.indices {
            for ai in updated[gi].actionGroups.indices {
                for ii in updated[gi].actionGroups[ai].items.indices {
                    updated[gi].actionGroups[ai].items[ii].isSelected =
                        selector.shouldSelect(updated[gi].actionGroups[ai].items[ii].riskLevel)
                }
            }
        }
        resultGroups = updated
    }

    public func startCleanup() {
        // 收集所有选中的 URL
        let selectedPaths: [String] = resultGroups.flatMap { group in
            group.actionGroups.isEmpty
                ? group.items.filter(\.isSelected).map(\.path)
                : group.actionGroups.flatMap { $0.items.filter(\.isSelected) }.map(\.path)
        }
        guard !selectedPaths.isEmpty else { return }

        let urls = selectedPaths.map { URL(fileURLWithPath: $0) }
        let cleanupEngine = CleanupEngine()

        Task { @MainActor in
            // Phase 1: 检测运行中应用
            let warnItems = cleanupEngine.detectWarnItems(for: selectedPaths)
            // (UI 层会在收到 warn 后弹出确认对话框 — 简化实现当前跳过)

            // Phase 2: 执行清理
            for await progress in cleanupEngine.cleanup(urls: urls) {
                if case .completed = progress.state {
                    print("[Cleanup] 完成: \(progress.completedItems)/\(progress.totalItems), "
                          + "\(progress.processedBytes) bytes. "
                          + "失败 \(progress.failedPaths.count) 个")
                }
                if case .failed = progress.state {
                    print("[Cleanup] 部分失败: \(progress.failedPaths.count) 个失败路径")
                }
            }

            // 清理后重置选择
            await refetchIncremental()
        }
    }

    // MARK: - Grouping

    public static func buildResultGroups(from entries: [FileEntry]) -> [ScanResultGroup] {
        // Group entries by subCategoryID first.
        let bySubCategory = Dictionary(grouping: entries) { Int($0.subCategoryID) }

        return bySubCategory.compactMap { subID, items -> ScanResultGroup? in
            // Within each subCategory, group by actionID (the 2nd-level grouping).
            let byAction = Dictionary(grouping: items) { Int($0.actionID) }
            let actionGroups: [ActionGroup] = byAction.compactMap { actionID, actionItems -> ActionGroup? in
                let appName = actionIDToAppName[actionID]
                let caution = actionIDToCaution[actionID]
                let title = actionIDToTitle[actionID] ?? "其他"
                let nodes = actionItems.map {
                    ScanResultNode(fileEntry: $0, appName: appName, cautionID: caution)
                }
                return ActionGroup(
                    id: actionID,
                    title: title,
                    appName: appName,
                    isRecommended: nodes.first?.isRecommended ?? true,
                    cautionID: caution,
                    items: nodes
                )
            }.sorted { $0.totalSize > $1.totalSize }

            // Pick the most common appName for the category header.
            let primaryApp = actionGroups.compactMap(\.appName).first
            let title = subCategoryTitles[subID] ?? "其他"

            return ScanResultGroup(
                id: subID,
                title: title,
                appName: primaryApp,
                items: [],
                actionGroups: actionGroups
            )
        }.sorted { $0.totalSize > $1.totalSize }
    }
}
