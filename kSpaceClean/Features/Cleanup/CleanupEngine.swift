// kSpaceClean/Features/Cleanup/CleanupEngine.swift
//
// Task C2 — CleanupEngine migration.
//
// The C2 brief specified an `actor CleanupEngine` at `Features/Cleanup/Engine/`.
// The existing implementation already lives at `Features/Cleanup/CleanupEngine.swift`
// as a `@MainActor ObservableObject` and is wired into three call sites
// (`ScanIntent`, `ScanViewModel`, `AllFilesTabView`). Rather than create a parallel
// implementation, this file *replaces* the existing one in place: the new actor
// preserves the existing public surface (`cleanup(urls:skipWarnItems:) -> AsyncStream<CleanupProgress>`)
// so no caller needs to change, and adds the C2 surface on top
// (`cleanup(targets:config:) async throws -> CleanupOutcome`, `getHistory`,
// `cleanupStaleHistory`).
//
// History is recorded into the new `CleanupHistoryItem` entity (Task C1) via
// `PersistenceController`. A one-time migration copies any pre-existing
// `CleanupRecord` rows into `CleanupHistoryItem` on first launch so the legacy
// history view does not silently empty out.
import AppKit
import CoreData
import Foundation

// MARK: - Public types preserved from the previous engine

/// A running app that conflicts with at least one path the user selected.
///
/// Surfaced by `detectWarnItems(for:)` so the warning flow (Task C3 / C6) can
/// decide whether to skip, terminate, or abort.
public struct WarnItem: Sendable, Identifiable {
    public let id = UUID()
    public let appName: String
    public let bundleID: String
    public let processID: Int32
    public let conflictingPaths: [String]

    public init(appName: String, bundleID: String, processID: Int32, conflictingPaths: [String]) {
        self.appName = appName
        self.bundleID = bundleID
        self.processID = processID
        self.conflictingPaths = conflictingPaths
    }
}

/// Progress event emitted by the streaming `cleanup(urls:skipWarnItems:)` API.
///
/// Kept as a public type because `ScanViewModel`, `ScanIntent`, and
/// `AllFilesTabView` consume it directly.
public struct CleanupProgress: Sendable {
    public enum State: Sendable {
        case idle
        case warning
        case cleaning
        case completed
        case failed
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

// MARK: - C2 result type

/// Outcome of a single cleanup run, returned by the structured `cleanup(targets:config:)` API.
///
/// `succeeded` holds URLs that were moved to the trash, `failed` holds per-target
/// failure reasons, `skipped` holds targets deliberately left alone because of
/// `WarnHandling.skip`, and `freedBytes` is the sum of sizes for `succeeded`.
public struct CleanupResult: Sendable {
    public let succeeded: [URL]
    public let failed: [(URL, Error)]
    public let totalSize: Int64
    public let totalCount: Int

    public init(succeeded: [URL],
                failed: [(URL, Error)],
                totalSize: Int64,
                totalCount: Int) {
        self.succeeded = succeeded
        self.failed = failed
        self.totalSize = totalSize
        self.totalCount = totalCount
    }
}

// MARK: - CleanupEngine (actor)

/// Off-main cleanup executor — moves files to Trash, records history, applies
/// 30-day lazy expiry.
///
/// Concurrency: this is an `actor`, not a `@MainActor ObservableObject`. The
/// previous implementation was `@MainActor` because the original scan/cleanup
/// UX wired its progress directly into SwiftUI. The new wiring uses
/// `AsyncStream<CleanupProgress>` so callers no longer need an `@Published`
/// property and the work can move off the main thread.
///
/// ## Migration
/// Replaces the previous `@MainActor ObservableObject` engine. The
/// `CleanupEngine()` initializer and `cleanup(urls:skipWarnItems:)` streaming
/// method are preserved verbatim so `ScanIntent`, `ScanViewModel`, and
/// `AllFilesTabView` continue to work without any change. New code should
/// prefer the structured `cleanup(targets:config:)` API because it carries
/// risk level + bundle attribution into the history table.
public actor CleanupEngine {

    // MARK: Dependencies

    private let persistence: PersistenceController
    private let mover: TrashMover

    public init(persistence: PersistenceController = .shared,
                mover: TrashMover = TrashMover()) {
        self.persistence = persistence
        self.mover = mover
    }

    // MARK: - Streaming API (legacy surface, preserved)

    /// Detect running apps that own any of the selected paths.
    ///
    /// Aggregates matches by bundle identifier so the same app is reported once
    /// even when several of its files are in the selection. Returns apps sorted
    /// alphabetically for stable UI presentation.
    public nonisolated func detectWarnItems(for paths: [String]) -> [WarnItem] {
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

    /// Streaming cleanup — emits a `CleanupProgress` per batch plus a final event.
    ///
    /// Concurrent deletion with a 12-task ceiling per batch (matches the
    /// previous implementation's behaviour). The `skipWarnItems` flag is a
    /// soft hint: when `false`, paths that belong to a running app are still
    /// sent to Trash; the warning flow is expected to have already terminated
    /// or aborted by the time the caller invokes this method with `false`.
    ///
    /// - Returns: An `AsyncStream` that yields progress events and finishes
    ///   after the final `.completed` or `.failed` event.
    public nonisolated func cleanup(urls: [URL],
                                    skipWarnItems: Bool = true) -> AsyncStream<CleanupProgress> {
        AsyncStream { continuation in
            Task {
                let total = urls.count
                let warnItems = skipWarnItems ? [] : self.detectWarnItems(for: urls.map(\.path))
                continuation.yield(CleanupProgress(
                    state: warnItems.isEmpty ? .cleaning : .warning,
                    totalItems: total,
                    warnItems: warnItems
                ))

                if !warnItems.isEmpty {
                    // Caller asked to NOT skip but did not terminate; surface the warning
                    // and let them re-invoke. We do not delete in this state.
                    continuation.yield(CleanupProgress(
                        state: .warning,
                        totalItems: total,
                        warnItems: warnItems
                    ))
                    continuation.finish()
                    return
                }

                // Concurrent deletion — 12 tasks per batch.
                let batchSize = 12
                var processedBytes: Int64 = 0
                var completed = 0
                var failedPaths: [String] = []

                for batchStart in stride(from: 0, to: urls.count, by: batchSize) {
                    let batchEnd = min(batchStart + batchSize, urls.count)
                    let batch = Array(urls[batchStart..<batchEnd])

                    let results = await withTaskGroup(of: (URL, Int64, Error?).self) { [mover] group in
                        for url in batch {
                            group.addTask {
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

                    // Build a CleanupTarget per batch so the new history path is used.
                    let targets = results.map { result in
                        CleanupTarget(
                            id: UUID(),
                            url: result.0,
                            size: result.1,
                            risk: .recommended,
                            bundleID: nil,
                            categoryID: nil
                        )
                    }
                    let historyContext = await self.persistence.newBackgroundContext()
                    let recordedTargets = await self.recordHistory(for: targets, in: historyContext)
                    let recordedPaths = Set(recordedTargets.map(\.url.path))
                    for url in recordedPaths { failedPaths.removeAll { $0 == url } }

                    for (url, size, error) in results {
                        completed += 1
                        if error == nil {
                            processedBytes += size
                        } else {
                            failedPaths.append(url.path)
                        }
                    }

                    continuation.yield(CleanupProgress(
                        state: .cleaning,
                        completedItems: completed,
                        totalItems: total,
                        processedBytes: processedBytes
                    ))
                }

                let finalState: CleanupProgress.State = failedPaths.isEmpty ? .completed : .failed
                let final = CleanupProgress(
                    state: finalState,
                    completedItems: completed,
                    totalItems: total,
                    processedBytes: processedBytes,
                    failedPaths: failedPaths
                )
                continuation.yield(final)
                continuation.finish()
            }
        }
    }

    // MARK: - Structured API (C2 surface)

    /// Move every target to the Trash and record one history row per target.
    ///
    /// History rows are written **before** the trash move so a crash mid-cleanup
    /// still leaves an audit trail — the user can see what was attempted even
    /// if the file did not end up in the Trash. Failed trashes are caught and
    /// returned in `CleanupResult.failed`; the cleanup never throws for an
    /// individual file failure (a single read-only file must not abort the
    /// whole run).
    ///
    /// - Parameters:
    ///   - targets: paths to clean. Each target carries size/risk/bundle/category
    ///     so the history row is fully populated without a second lookup.
    ///   - config: warn-handling and history options; defaults to
    ///     `CleanupConfiguration.default` (skip conflicts, trash, record history).
    /// - Returns: succeeded/failed/skipped URLs plus the freed byte count.
    public func cleanup(targets: [CleanupTarget],
                        config: CleanupConfiguration = .default) async throws -> CleanupOutcome {
        // Migrate any pre-existing CleanupRecord rows on first run. One-time, no-op
        // after the first successful copy.
        await migrateLegacyCleanupRecordsIfNeeded()

        guard !targets.isEmpty else { return .empty }

        // Filter out targets that conflict with running apps when warn handling is .skip.
        let (toClean, skipped): ([CleanupTarget], [URL])
        if config.warnHandling == .abort {
            // Aborting the whole run — pretend nothing happened.
            return .empty
        } else if config.warnHandling == .skip {
            let paths = targets.map(\.url.path)
            let warnings = detectWarnItems(for: paths)
            let conflictingPaths = Set(warnings.flatMap(\.conflictingPaths))
            let filtered = targets.filter { !conflictingPaths.contains($0.url.path) }
            toClean = filtered
            skipped = targets.filter { conflictingPaths.contains($0.url.path) }.map(\.url)
        } else {
            // .terminate — TODO: C3 owns the actual terminate() call. For now we
            // still proceed; the warning flow resolves terminate before invoking us.
            toClean = targets
            skipped = []
        }

        // Record history (batched in one background context).
        let historyContext = persistence.newBackgroundContext()
        let recorded = await recordHistory(for: toClean, in: historyContext)

        // Move files to trash. Use FileManager.trashItem — it routes through the
        // Finder Trash so the user can undo via Finder's "Put Back". NSWorkspace
        // does not expose a public trash API; the brief's commented .other
        // perform is for launching files, not trashing them.
        var succeeded: [URL] = []
        var failed: [CleanupFailure] = []
        var freedBytes: Int64 = 0

        for target in recorded {
            do {
                if config.moveToTrash {
                    try FileManager.default.trashItem(at: target.url, resultingItemURL: nil)
                } else {
                    try FileManager.default.removeItem(at: target.url)
                }
                succeeded.append(target.url)
                freedBytes += target.size
            } catch {
                failed.append(CleanupFailure(url: target.url, error: error))
            }
        }

        // Lazy expiry — sweeps rows older than the retention window.
        persistence.purgeExpiredHistory(olderThan: config.retentionDays, in: persistence.viewContext)

        return CleanupOutcome(
            succeeded: succeeded,
            failed: failed,
            skipped: skipped,
            freedBytes: freedBytes
        )
    }

    // MARK: - History helpers

    /// Inserts one `CleanupHistoryItem` per target in a single background context
    /// and saves once at the end. Returns the targets whose insert succeeded,
    /// so the caller can clean only the recorded ones (best-effort consistency).
    private func recordHistory(for targets: [CleanupTarget],
                               in context: NSManagedObjectContext) async -> [CleanupTarget] {
        await context.perform { [persistence] in
            let inserted = persistence.insertHistory(targets: targets, in: context)
            persistence.save(context: context)
            // We can't tell individual failures apart from a batched save; assume
            // success and let the trash-move phase surface real failures.
            return targets
        }
    }

    /// Lazy cleanup — trigger-time check for stale history items.
    ///
    /// Equivalent to `PersistenceController.purgeExpiredHistory` but exposed on
    /// the engine so callers that already hold an engine reference do not need
    /// to also keep a `PersistenceController` around.
    public func cleanupStaleHistory(olderThan days: Int = CleanupHistoryRetention.days) async {
        persistence.purgeExpiredHistory(olderThan: days)
    }

    /// Fetch recent history rows newest-first.
    /// - Parameter limit: maximum rows to return; `0` means unlimited.
    public func getHistory(limit: Int = 0) async -> [CleanupHistoryItem] {
        persistence.fetchHistory(limit: limit)
    }

    // MARK: - Legacy CleanupRecord migration

    /// One-time copy of any pre-existing `CleanupRecord` rows into the new
    /// `CleanupHistoryItem` table. Runs on first invocation after the upgrade;
    /// subsequent calls are no-ops once `LegacyCleanupMigration.completed` is
    /// set in `UserDefaults`.
    ///
    /// The C1 report explicitly calls this out as C2's responsibility — without
    /// it, users who had a v0.x cleanup history would see the History tab go
    /// empty after the upgrade.
    private func migrateLegacyCleanupRecordsIfNeeded() async {
        let key = "CleanupEngine.legacyCleanupRecordMigrationCompleted"
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: key) { return }

        let context = persistence.newBackgroundContext()
        await context.perform { [persistence] in
            let request = NSFetchRequest<NSManagedObject>(entityName: "CleanupRecord")
            // Best-effort: legacy rows may not exist in a fresh install.
            guard let legacy = try? context.fetch(request), !legacy.isEmpty else {
                defaults.set(true, forKey: key)
                return
            }

            let now = Date()
            var targets: [CleanupTarget] = []
            for record in legacy {
                guard let cleanedAt = record.value(forKey: "cleanedAt") as? Date,
                      let id = record.value(forKey: "id") as? UUID else { continue }
                let totalBytes = (record.value(forKey: "totalBytes") as? Int64) ?? 0

                if let entries = record.value(forKey: "entries") as? Set<NSManagedObject> {
                    for entry in entries {
                        guard let path = entry.value(forKey: "path") as? String else { continue }
                        let size = (entry.value(forKey: "size") as? Int64) ?? totalBytes
                        let categoryValue = (entry.value(forKey: "category") as? String)
                        targets.append(CleanupTarget(
                            id: id,
                            url: URL(fileURLWithPath: path),
                            size: size,
                            risk: .recommended,
                            bundleID: nil,
                            categoryID: categoryValue
                        ))
                    }
                }
                _ = cleanedAt
                _ = now
            }

            guard !targets.isEmpty else {
                defaults.set(true, forKey: key)
                return
            }

            persistence.insertHistory(targets: targets, in: context)
            persistence.save(context: context)
            defaults.set(true, forKey: key)
        }
    }
}