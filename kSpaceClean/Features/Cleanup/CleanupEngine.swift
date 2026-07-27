import Foundation
import AppKit
import CommonUtils

// MARK: - Warn Item

/// 警告项 — 当被选中的文件属于正在运行的应用时给出提示
public struct WarnItem: Sendable, Identifiable {
    public let id = UUID()
    public let appName: String
    public let bundleID: String
    public let processID: Int32
    public let conflictingPaths: [String]
}

// MARK: - Cleanup Progress

public struct CleanupProgress: Sendable {
    public enum State: Sendable {
        case idle, warning, cleaning, completed, failed
    }
    public let state: State
    public let completedItems: Int
    public let totalItems: Int
    public let processedBytes: Int64
    public let warnItems: [WarnItem]
    public let failedPaths: [String]

    public init(state: State = .idle,
                completedItems: Int = 0,
                totalItems: Int = 0,
                processedBytes: Int64 = 0,
                warnItems: [WarnItem] = [],
                failedPaths: [String] = []) {
        self.state = state
        self.completedItems = completedItems
        self.totalItems = totalItems
        self.processedBytes = processedBytes
        self.warnItems = warnItems
        self.failedPaths = failedPaths
    }
}

// MARK: - Cleanup Confirmation Level

/// 4-level cleanup confirmation routing (v3 spec §2.6)
public enum CleanupConfirmationLevel: Sendable, Equatable {
    case low         // 仅含推荐+可选项 → 一键确认
    case medium      // 含注意项 → 列表逐项确认
    case high        // 含危险项或运行中应用 → 警告流
    case irreversible // 跳过废纸篓 → 输入DELETE确认

    public static func from(riskLevels: [RiskLevel], hasWarnItems: Bool) -> CleanupConfirmationLevel {
        if riskLevels.contains(.dangerous) || hasWarnItems { return .high }
        if riskLevels.contains(.caution) { return .medium }
        return .low
    }
}

// MARK: - Cleanup Engine

/// 高层清理执行器 — 完成以下工作:
/// 1. 检测被选中的条目中是否有运行中应用的文件（warn items）
/// 2. 使用 TaskGroup 并发删除
/// 3. 每批后通过 AsyncStream 推送进度
@MainActor
public final class CleanupEngine: ObservableObject {
    @Published public private(set) var progress: CleanupProgress = CleanupProgress()
    @Published public private(set) var lastResult: CleanupProgress?

    private let mover = TrashMover()
    private let history = CleanupHistory()

    public init() {}

    /// 检测正运行应用中被选中的路径。
    /// - Returns: 冲突警告项数组（按 bundleID 聚合）
    public func detectWarnItems(for paths: [String]) -> [WarnItem] {
        let running = NSWorkspace.shared.runningApplications
        var warnByBundle: [String: WarnItem] = [:]

        for app in running {
            guard let appURL = app.bundleURL,
                  let bundleID = app.bundleIdentifier else { continue }
            let appPath = appURL.path
            for path in paths where path == appPath || path.hasPrefix(appPath + "/") || path.hasPrefix(appPath) {
                var item = warnByBundle[bundleID]
                if item == nil {
                    item = WarnItem(
                        appName: app.localizedName ?? bundleID,
                        bundleID: bundleID,
                        processID: app.processIdentifier,
                        conflictingPaths: []
                    )
                }
                warnByBundle[bundleID] = WarnItem(
                    appName: item!.appName,
                    bundleID: bundleID,
                    processID: item!.processID,
                    conflictingPaths: item!.conflictingPaths + [path]
                )
            }
        }
        return Array(warnByBundle.values).sorted { $0.appName < $1.appName }
    }

    /// 执行清理 — 输出 AsyncStream<CleanupProgress>。
    /// 调用方应在 `if warns.isEmpty` 或用户确认后启动。
    public func cleanup(urls: [URL], skipWarnItems: Bool = true) -> AsyncStream<CleanupProgress> {
        AsyncStream { continuation in
            Task {
                let total = urls.count
                continuation.yield(CleanupProgress(state: .cleaning, totalItems: total))

                // 并发删除 — 每批 12 个并发任务
                let batchSize = 12
                var succeeded: [URL] = []
                var failed: [String] = []
                var processedBytes: Int64 = 0
                var completed = 0

                for batchStart in stride(from: 0, to: urls.count, by: batchSize) {
                    let batchEnd = min(batchStart + batchSize, urls.count)
                    let batch = Array(urls[batchStart..<batchEnd])

                    let results = await withTaskGroup(of: (URL, Int64, Error?).self) { group in
                        for url in batch {
                            group.addTask { [mover] in
                                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
                                do {
                                    var trashedURL: NSURL?
                                    try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
                                    if let trashURL = trashedURL as? URL {
                                        _ = try? await mover.snapshotIfPossible(original: url, trashURL: trashURL)
                                    }
                                    return (url, size, nil)
                                } catch {
                                    return (url, size, error)
                                }
                            }
                        }
                        var collected: [(URL, Int64, Error?)] = []
                        for await r in group { collected.append(r) }
                        return collected
                    }

                    for (url, size, error) in results {
                        completed += 1
                        if error == nil {
                            succeeded.append(url)
                            processedBytes += size
                        } else {
                            failed.append(url.path)
                        }
                    }

                    continuation.yield(CleanupProgress(
                        state: .cleaning,
                        completedItems: completed,
                        totalItems: total,
                        processedBytes: processedBytes
                    ))
                }

                let final = CleanupProgress(
                    state: failed.isEmpty ? .completed : .failed,
                    completedItems: succeeded.count,
                    totalItems: total,
                    processedBytes: processedBytes,
                    warnItems: [],
                    failedPaths: failed
                )
                self.lastResult = final
                await MainActor.run { self.progress = final }
                continuation.yield(final)
                continuation.finish()
            }
        }
    }
}

// MARK: - TrashMover Snapshot Helper

extension TrashMover {
    /// Best-effort snapshot helper — nil-safe for use inside concurrent Tasks
    func snapshotIfPossible(original: URL, trashURL: URL) async -> TrashSnapshot? {
        guard let values = try? original.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return nil
        }
        return TrashSnapshot(
            originalPath: original.path,
            trashPath: trashURL.path,
            fileSize: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate ?? Date()
        )
    }
}
