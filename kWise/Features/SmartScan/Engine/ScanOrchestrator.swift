// kWise/Features/SmartScan/Engine/ScanOrchestrator.swift
//
// Drives the parallel scan pipeline that turns the v3 4-level scan-result
// tree into a populated `ScanCategory` → `ScanSubCategory` → `ScanAction`
// → `ScanResult` cascade.
//
// Responsibilities:
//   1. Fan out per-category scanning across a `withTaskGroup` so the eight
//      built-in categories run concurrently (one Task per category).
//   2. For each file discovered by `FileEnumerator`, classify its risk
//      tier via `RiskClassifier.classify(path:)` (Task A9 — subsumes the
//      blocked Task B0).
//   3. For each file, ask `BundleIDResolver.resolve(path:)` which app, if
//      any, owns the path so cleanup warnings can mention the right app.
//   4. Emit `ScanProgress` events on an `AsyncStream` so the SwiftUI layer
//      (`ScanResultsView` / `ScanProgressView`) can render live state.
//
// Concurrency: `ScanOrchestrator` is an `actor` so its `categoryDefs`,
// `riskClassifier`, and `bundleIDResolver` are accessed under actor
// isolation. The `AsyncStream` returned by `startScan()` is consumed from
// any isolation domain — `AsyncStream.Continuation` is `Sendable` because
// every yielded value is `Sendable`.

import Foundation
import FileScanner

// MARK: - Category Definition

/// Static description of one top-level scan category.
///
/// The v3 spec (CLAUDE.md §8.2) requires that the **6 category skeletons
/// are visible before a scan starts**, with sub-categories / actions /
/// results only materialising after the scan visits their paths. The
/// orchestrator uses `CategoryDefinition.paths` to drive the
/// `FileEnumerator`, then folds the discovered files back into the
/// pre-rendered `ScanCategory` rows.
public struct CategoryDefinition: Sendable, Identifiable, Hashable {
    public let id: String              // e.g. "system.cache"
    public let title: String           // e.g. "系统缓存"
    public let tooltip: String?        // Surfaced as Help tag on the row
    public let paths: [String]         // Root paths to scan (tilde-expanded)
    public let riskLevel: RiskLevel    // Category-level default risk

    public init(
        id: String,
        title: String,
        tooltip: String? = nil,
        paths: [String],
        riskLevel: RiskLevel = .recommended
    ) {
        self.id = id
        self.title = title
        self.tooltip = tooltip
        self.paths = paths
        self.riskLevel = riskLevel
    }

    /// The v1.0 default category set — six top-level buckets mirroring the
    /// kWise marketing copy ("系统缓存 / 应用缓存 / 上网垃圾 /
    /// 邮件附件 / 开发者垃圾 / 系统日志"). Paths use `~/` so the
    /// enumerator's tilde expansion handles sandboxed home lookups.
    public static let defaults: [CategoryDefinition] = [
        CategoryDefinition(
            id: "system.cache",
            title: "系统缓存",
            tooltip: "由系统或应用自动重建的缓存文件",
            paths: ["~/Library/Caches", "/Library/Caches"],
            riskLevel: .recommended
        ),
        CategoryDefinition(
            id: "app.cache",
            title: "应用缓存",
            tooltip: "应用主动写入的缓存或临时数据",
            paths: ["~/Library/Application Support", "~/Library/Containers"],
            riskLevel: .caution
        ),
        CategoryDefinition(
            id: "browser.junk",
            title: "上网垃圾",
            tooltip: "浏览器历史、Cookie 与本地存储",
            paths: ["~/Library/Safari", "~/Library/Cookies"],
            riskLevel: .caution
        ),
        CategoryDefinition(
            id: "mail.attachments",
            title: "邮件附件",
            tooltip: "已下载的邮件附件与本地缓存",
            paths: ["~/Library/Mail"],
            riskLevel: .caution
        ),
        CategoryDefinition(
            id: "developer.junk",
            title: "开发者垃圾",
            tooltip: "Xcode DerivedData、模拟器缓存与 SPM 工作目录",
            paths: ["~/Library/Developer/Xcode/DerivedData",
                    "~/Library/Developer/CoreSimulator/Caches",
                    "~/Library/Caches/org.swift.swiftpm"],
            riskLevel: .recommended
        ),
        CategoryDefinition(
            id: "system.logs",
            title: "系统日志",
            tooltip: "诊断日志与崩溃报告",
            paths: ["/private/var/log", "/Library/Logs",
                    "~/Library/Logs/DiagnosticReports"],
            riskLevel: .recommended
        )
    ]
}

// MARK: - Category Event

/// One `ScanCategory` yielded by the orchestrator's category stream as soon
/// as the worker for that category finishes its walk.
///
/// Consumers (`ScanEngineStream`) fold these into the published tree so
/// `ScanResultsViewModel.categories` populates incrementally rather than
/// only after the whole scan finishes. Carries a `categoryID` so the stream
/// consumer can correlate the event with the corresponding
/// `ScanProgress.categoryProgress` row.
public struct ScanCategoryEvent: Sendable {
    public let category: ScanCategory
    public let categoryID: String
    public let filesFound: Int
    public let totalSize: Int64

    public init(category: ScanCategory, filesFound: Int, totalSize: Int64) {
        self.category = category
        self.categoryID = category.categoryID
        self.filesFound = filesFound
        self.totalSize = totalSize
    }
}

// MARK: - Scan Orchestrator

/// Parallel fan-out scanner — runs one `Task` per `CategoryDefinition`,
/// aggregates results into the existing `ScanCategory` tree, and emits
/// `ScanProgress` snapshots as work completes.
///
/// Wiring (Task B0 subsumption):
/// * Each enumerated file is classified by `RiskClassifier.classify(path:)`
///   to attach a `RiskLevel` to the resulting `ScanResult` row.
/// * Each file's owning app is resolved by `BundleIDResolver.resolve(path:)`
///   to populate the `ScanSubCategory.bundleID` / `appName` fields used by
///   `WarningDetectionService` (Task C3) and the cleanup sheet (C4).
///
/// Lifecycle:
/// * `startScan()` returns an `AsyncStream<ScanProgress>` — call once.
/// * The stream finishes with `.completed` after every category worker
///   has returned (or `.failed(message)` if the underlying enumerator
///   throws).
/// * The orchestrator itself is single-shot — instantiate a fresh one
///   per scan so `categoriesScanned` starts at zero.
public actor ScanOrchestrator {
    // MARK: Dependencies
    private let categoryDefs: [CategoryDefinition]
    private let riskClassifier: RiskClassifier
    private let bundleIDResolver: BundleIDResolver
    private let fileEnumerator: FileEnumerator

    // MARK: Mutable state
    private var categoriesScanned: Int = 0
    private var isCancelled: Bool = false
    /// Monotonic counter bumped by every `startScan()`. Guards against a
    /// *stale* scan's worker task (or a lingering `categoryStream()` poller)
    /// writing its terminal state into a *newer* scan's freshly-reset
    /// buffers — the re-entrancy bug where a second scan on the same
    /// orchestrator was killed prematurely by the first scan's tail writes.
    /// `startScan()` captures the current epoch and every state mutation
    /// site checks it before writing.
    private var scanEpoch: UInt64 = 0
    /// Cached `ScanCategory` events ready for the `categoryStream()` consumer.
    /// Populated as workers complete (writes from the actor); drained lazily
    /// on first `categoryStream()` call.
    private var pendingCategoryEvents: [ScanCategoryEvent] = []
    /// Set to `true` once the final `.completed`/`.failed`/`.cancelled` event
    /// has been written, so `categoryStream()` knows when to finish.
    private var hasFinishedScan: Bool = false
    private var finalTerminalState: ScanProgress = .init(
        state: .idle,
        filesDiscovered: 0,
        totalBytes: 0,
        currentDirectory: "",
        currentCategory: "",
        currentSubCategory: "",
        errors: [],
        finishedAt: nil,
        speed: .medium,
        categoryProgress: [],
        currentStage: .cache,
        currentNodePath: nil,
        stats: ScanStats()
    )

    // MARK: Live progress composer (Task A1)
    private var liveCategoryProgress: [String: CategoryProgress] = [:]
    private var runningFiles: Int = 0
    private var runningBytes: Int64 = 0
    private var scanStartedAt: Date = Date()
    private var currentNodePath: String?
    private var currentCategoryID: String = ""
    private var lastYieldAt: Date = .distantPast
    private var activeProgressContinuation: AsyncStream<ScanProgress>.Continuation?

    // MARK: Init

    /// Default initializer used by `ScanEngine.startScan()` (Task B4).
    ///
    /// C6 fix: if `bundleIDResolver` is its default value (a fresh actor with
    /// nothing loaded), the init eagerly loads `bundleIDMapping.json` from
    /// `Bundle.main`. The previous behaviour shipped an empty mapping and
    /// the orchestrator was effectively running with 25 hardcoded apps —
    /// every path resolved to "no app, generic category bucket". We now
    /// load the full mapping at boot so the v3 cascade algorithm sees the
    /// real attribution.
    public init(
        categoryDefinitions: [CategoryDefinition] = CategoryDefinition.defaults,
        riskClassifier: RiskClassifier = RiskClassifier(),
        bundleIDResolver: BundleIDResolver = BundleIDResolver(),
        fileEnumerator: FileEnumerator = FileEnumerator()
    ) {
        self.categoryDefs = categoryDefinitions
        self.riskClassifier = riskClassifier
        self.bundleIDResolver = bundleIDResolver
        self.fileEnumerator = fileEnumerator

        // C6: kick off the JSON load eagerly. The init is synchronous but
        // `BundleIDResolver.load(from:)` is `async`; we fire-and-forget
        // the task from a detached context so we do not block the caller.
        // The resolver's own actor-isolation guarantees that a slow load
        // will not race with subsequent `resolve(path:)` calls (they
        // observe the actor's in-memory state).
        if let url = Bundle.main.url(forResource: "bundleIDMapping", withExtension: "json") {
            Task.detached(priority: .utility) { [bundleIDResolver] in
                await bundleIDResolver.load(from: url)
            }
        }
    }

    // MARK: Cancellation

    /// Cooperative cancellation — flips an internal flag; the running
    /// TaskGroup observes the flag at every category boundary and exits
    /// early. (We intentionally do NOT call `Task.cancel()` on the
    /// TaskGroup because `FileEnumerator.walk` uses `FileManager` and we
    /// cannot interrupt a mid-`nextObject()` call atomically.)
    ///
    /// Also parks a terminal `.cancelled` snapshot so any `categoryStream()`
    /// consumer that attaches after cancellation sees the scan is done.
    public func cancel() {
        isCancelled = true
        if !hasFinishedScan {
            finalTerminalState = ScanProgress(
                state: .cancelled,
                filesDiscovered: 0,
                totalBytes: 0,
                errors: [],
                finishedAt: Date(),
                speed: .medium
            )
            hasFinishedScan = true
        }
    }

    // MARK: Scan Entry Point

    /// Start a parallel scan. The returned `AsyncStream` yields one
    /// `ScanProgress` per completed category plus a final `.completed`
    /// snapshot; consumers can iterate with `for await progress in stream`.
    ///
    /// - Returns: An `AsyncStream<ScanProgress>` that finishes once every
    ///   category worker has returned (or been short-circuited by
    ///   `cancel()`).
    ///
    /// C2: resets the per-scan buffers (`pendingCategoryEvents`,
    /// `hasFinishedScan`, `finalTerminalState`) so a second `startScan()` on
    /// the same orchestrator instance starts clean. The previous
    /// implementation's buffers would have leaked state across scans.
    public func startScan() -> AsyncStream<ScanProgress> {
        // Bump the epoch first: any *stale* scan's runScan tail or
        // categoryStream() poller that mutates shared state checks
        // `epoch == scanEpoch` before writing, so this immediately
        // invalidates whatever the previous scan left in flight.
        scanEpoch &+= 1
        let epoch = scanEpoch

        // Reset per-scan buffers.
        isCancelled = false
        pendingCategoryEvents.removeAll(keepingCapacity: true)
        hasFinishedScan = false
        finalTerminalState = ScanProgress(
            state: .idle,
            filesDiscovered: 0,
            totalBytes: 0,
            currentDirectory: "",
            currentCategory: "",
            currentSubCategory: "",
            errors: [],
            finishedAt: nil,
            speed: .medium,
            categoryProgress: [],
            currentStage: .cache,
            currentNodePath: nil,
            stats: ScanStats()
        )

        // Seed the live composer for this scan (Task A1). Row order follows
        // `categoryDefs` and is preserved by every `composeSnapshot`.
        liveCategoryProgress = Dictionary(
            uniqueKeysWithValues: categoryDefs.map { ($0.id, Self.makeCategoryProgress(for: $0)) }
        )
        runningFiles = 0
        runningBytes = 0
        scanStartedAt = Date()
        currentNodePath = nil
        currentCategoryID = categoryDefs.first?.id ?? ""
        lastYieldAt = .distantPast
        activeProgressContinuation = nil

        return AsyncStream { continuation in
            // Spawn the worker task on the orchestrator actor so all
            // shared state mutations are serialised. The continuation
            // is `Sendable` so we can pass it across isolation domains.
            let task = Task { [weak self] in
                guard let self else {
                    continuation.yield(ScanProgress(state: .failed("orchestrator deallocated"),
                                                    finishedAt: Date()))
                    continuation.finish()
                    return
                }
                await self.runScan(continuation: continuation, epoch: epoch)
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: Worker

    /// Main pipeline — fans out one Task per category, then aggregates.
    private func runScan(
        continuation: AsyncStream<ScanProgress>.Continuation,
        epoch: UInt64
    ) async {
        // F8: signpost marker so an Instruments run can attribute the
        // orchestrator's wall time without sifting through stack frames.
        let _ = PerfInterval("scan.orchestrate")
        activeProgressContinuation = continuation
        defer { activeProgressContinuation = nil }
        var completed = 0
        var failedCategories: [String] = []

        // Initial snapshot — UI shows total=6 immediately so the
        // progress ring can render even before the first Task returns.
        continuation.yield(composeSnapshot(state: .scanning))

        await withTaskGroup(of: ScanOutcome.self) { group in
            for def in categoryDefs {
                group.addTask { [riskClassifier, bundleIDResolver, fileEnumerator, weak self] in
                    await Self.scanCategory(
                        def,
                        classifier: riskClassifier,
                        resolver: bundleIDResolver,
                        enumerator: fileEnumerator,
                        onProgress: { delta in
                            guard let self else { return }
                            await self.recordProgress(delta, epoch: epoch)
                        }
                    )
                }
            }

            for await outcome in group {
                // Epoch guard: if a newer `startScan()` bumped the epoch
                // while this group was running, this scan is stale — stop
                // folding outcomes and let the fresh scan own the state.
                if Task.isCancelled || isCancelled || epoch != scanEpoch { break }
                completed += 1
                if let err = outcome.error {
                    failedCategories.append("\(outcome.category.title): \(err)")
                }

                // C2: enqueue the per-category payload so `categoryStream()`
                // consumers can fold the tree incrementally instead of
                // waiting for the whole scan to complete.
                pendingCategoryEvents.append(ScanCategoryEvent(
                    category: outcome.category,
                    filesFound: outcome.fileCount,
                    totalSize: outcome.bytes
                ))

                await markCategoryCompleted(outcome, epoch: epoch)
                continuation.yield(composeSnapshot(state: .scanning))
            }
        }

        let terminalState: ScanProgress
        if Task.isCancelled || isCancelled {
            terminalState = composeSnapshot(state: .cancelled, finishedAt: Date())
        } else if !failedCategories.isEmpty {
            // Partial failure: surface the first error but still mark as
            // completed so the user can review what was found.
            terminalState = composeSnapshot(
                state: .failed(failedCategories.first ?? "unknown"),
                finishedAt: Date()
            )
        } else {
            terminalState = composeSnapshot(state: .completed, finishedAt: Date())
        }
        // Epoch guard: if a newer `startScan()` bumped the epoch while we
        // were folding outcomes, our tail must NOT write terminal state into
        // the fresh scan's reset buffers — that was the re-entrancy bug that
        // killed a second scan prematurely. Finish our own continuation and
        // let the newer runScan own the state.
        guard epoch == scanEpoch else {
            continuation.finish()
            return
        }
        // C2: park the terminal snapshot so categoryStream() finishes in sync
        // with the progress stream.
        finalTerminalState = terminalState
        hasFinishedScan = true
        continuation.yield(terminalState)
        continuation.finish()

        // Reset internal counters so the same actor can be reused for a
        // second scan (we do not currently expose this, but it keeps the
        // semantics correct for tests that drive multiple cycles).
        categoriesScanned = completed
    }

    // MARK: - Live progress composer (Task A1)

    /// Folds one per-file discovery event into the live counters and emits a
    /// throttled snapshot. Epoch-guarded so a stale scan cannot write into a
    /// newer scan's buffers.
    private func recordProgress(_ delta: ScanDelta, epoch: UInt64) async {
        guard epoch == scanEpoch else { return }
        runningFiles += delta.filesIncrement
        runningBytes += delta.bytesIncrement
        currentNodePath = delta.filePath
        currentCategoryID = delta.categoryID
        if var row = liveCategoryProgress[delta.categoryID] {
            row = CategoryProgress(
                id: row.id,
                title: row.title,
                status: row.status == .pending ? .scanning : row.status,
                subCategories: row.subCategories,
                filesFound: row.filesFound + delta.filesIncrement,
                totalSize: row.totalSize + delta.bytesIncrement
            )
            liveCategoryProgress[delta.categoryID] = row
        }
        await yieldSnapshot()
    }

    /// Marks one category worker's outcome complete in the live rows, then emits.
    private func markCategoryCompleted(_ outcome: ScanOutcome, epoch: UInt64) async {
        guard epoch == scanEpoch,
              var row = liveCategoryProgress[outcome.category.categoryID] else { return }
        row = CategoryProgress(
            id: row.id,
            title: row.title,
            status: .completed,
            subCategories: row.subCategories,
            filesFound: outcome.fileCount,
            totalSize: outcome.bytes
        )
        liveCategoryProgress[outcome.category.categoryID] = row
        await yieldSnapshot()
    }

    /// Throttled snapshot emission (~max 10/s) so high-frequency per-file
    /// deltas do not flood the AsyncStream or the UI.
    private func yieldSnapshot() async {
        let now = Date()
        guard now.timeIntervalSince(lastYieldAt) >= 0.1 else { return }
        lastYieldAt = now
        activeProgressContinuation?.yield(composeSnapshot(state: .scanning))
    }

    /// Composes the full live `ScanProgress` from the composer state.
    /// Row order follows `categoryDefs` (definition order preserved). On
    /// `.completed` any still-pending/scanning row is force-completed so the
    /// ring reaches 100% even when a category produced zero files.
    private func composeSnapshot(
        state: ScanProgress.State,
        finishedAt: Date? = nil
    ) -> ScanProgress {
        let now = finishedAt ?? Date()
        let rows = categoryDefs.compactMap { def -> CategoryProgress? in
            guard var row = liveCategoryProgress[def.id] else { return nil }
            if state == .completed, row.status == .pending || row.status == .scanning {
                row = CategoryProgress(
                    id: row.id,
                    title: row.title,
                    status: .completed,
                    subCategories: row.subCategories,
                    filesFound: row.filesFound,
                    totalSize: row.totalSize
                )
            }
            return row
        }
        let elapsed = now.timeIntervalSince(scanStartedAt)
        let filesPerSecond = elapsed > 0 ? Double(runningFiles) / elapsed : 0
        return ScanProgress(
            state: state,
            filesDiscovered: runningFiles,
            totalBytes: runningBytes,
            currentDirectory: currentNodePath ?? "",
            currentCategory: liveCategoryProgress[currentCategoryID]?.title ?? currentCategoryID,
            currentSubCategory: "",
            errors: [],
            finishedAt: finishedAt,
            speed: .medium,   // ScanSpeed type; the live 速度 column reads stats.filesPerSecond
            categoryProgress: rows,
            currentStage: Self.stage(for: currentCategoryID) ?? .cache,
            currentNodePath: currentNodePath,
            stats: ScanStats(
                discoveredSize: runningBytes,
                fileCount: runningFiles,
                elapsed: elapsed,
                filesPerSecond: filesPerSecond
            )
        )
    }

    // MARK: - Category stream (C2)

    /// AsyncStream of `ScanCategory` payloads — one per completed category,
    /// followed by a sentinel `.completed`/`.failed`/`.cancelled` state so
    /// consumers know when to stop.
    ///
    /// Drains the orchestrator's internal event buffer. Bounded so we never
    /// grow the buffer indefinitely on long scans; uses `.bufferingNewest(4096)`
    /// which drops the oldest events if the consumer falls behind.
    public func categoryStream() -> AsyncStream<ScanCategoryStreamEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(4096)) { continuation in
            Task { [weak self] in
                guard let self else { continuation.finish(); return }
                // Capture the epoch this consumer is tied to. Every state read
                // below is only meaningful while `scanEpoch` still equals it;
                // if a newer scan bumps the epoch, this consumer is stale and
                // sees itself as "finished" (see `isFinishedForEpoch`).
                let epoch = await self.scanEpoch
                // Drain anything produced before the consumer attached.
                let buffered = await self.drainPendingCategoryEvents(epoch: epoch)
                for event in buffered { continuation.yield(.category(event)) }
                // If the scan has already finished (or a newer scan superseded
                // it), emit the terminal event and stop.
                if await self.isFinishedForEpoch(epoch) {
                    let terminal = await self.terminalStateForEpoch(epoch)
                        ?? ScanProgress(state: .cancelled, finishedAt: Date())
                    continuation.yield(.terminal(terminal))
                    continuation.finish()
                    return
                }
                // Otherwise poll the buffer until the terminal state arrives.
                // Polling is intentional: the actor's isolation model means we
                // can only re-enter via `await`; the wrapper transforms the
                // polling into a 50ms cadence so we don't burn CPU.
                while !(await self.isFinishedForEpoch(epoch)) {
                    try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
                    if Task.isCancelled { break }
                    let more = await self.drainPendingCategoryEvents(epoch: epoch)
                    for event in more { continuation.yield(.category(event)) }
                }
                // Final drain: events can land between the last poll iteration
                // and the terminal-state write, so flush once more before
                // yielding `.terminal` — otherwise the final category batch
                // silently disappears (the "scan said clean" class of bug).
                let remaining = await self.drainPendingCategoryEvents(epoch: epoch)
                for event in remaining { continuation.yield(.category(event)) }
                let terminal = await self.terminalStateForEpoch(epoch)
                    ?? ScanProgress(state: .cancelled, finishedAt: Date())
                continuation.yield(.terminal(terminal))
                continuation.finish()
            }
        }
    }

    /// Pop every event currently buffered and return them in arrival order.
    /// Only drains when `epoch` is still the live scan's epoch — a stale
    /// consumer must not steal events enqueued by a newer scan.
    private func drainPendingCategoryEvents(epoch: UInt64) -> [ScanCategoryEvent] {
        guard epoch == scanEpoch else { return [] }
        let events = pendingCategoryEvents
        pendingCategoryEvents.removeAll(keepingCapacity: true)
        return events
    }

    /// True when the scan identified by `epoch` is over: either a newer scan
    /// has bumped the epoch (stale), or the terminal state has been parked.
    private func isFinishedForEpoch(_ epoch: UInt64) -> Bool {
        epoch != scanEpoch || hasFinishedScan
    }

    /// The parked terminal snapshot for `epoch`, or `nil` when `epoch` is
    /// stale (a newer scan owns the buffers, so reading `finalTerminalState`
    /// would leak cross-scan state).
    private func terminalStateForEpoch(_ epoch: UInt64) -> ScanProgress? {
        guard epoch == scanEpoch else { return nil }
        return finalTerminalState
    }

    // MARK: Category Worker (static so it can run inside the TaskGroup)

    /// Result of one category worker — minimal payload so the orchestrator
    /// can fold N outcomes into a single `ScanProgress` snapshot without
    /// holding the whole `ScanCategory` tree in memory.
    private struct ScanOutcome: Sendable {
        let category: ScanCategory
        let bytes: Int64
        let fileCount: Int
        let error: String?
    }

    /// Walks every path under `def.paths`, classifies each file's risk,
    /// and rolls everything up into a single `ScanCategory`.
    ///
    /// **This subsumes Task B0**: the `RiskClassifier` is invoked once
    /// per file (rather than per path), so the same logic that powers the
    /// "is this dangerous?" warning also drives the per-row `RiskLevel`
    /// badge. The classifier is injected (not instantiated here) so tests
    /// can supply a deterministic stub.
    private static func scanCategory(
        _ def: CategoryDefinition,
        classifier: RiskClassifier,
        resolver: BundleIDResolver,
        enumerator: FileEnumerator,
        onProgress: (ScanDelta) async -> Void
    ) async -> ScanOutcome {
        var subItems: [ScanSubCategory] = []
        var totalSize: Int64 = 0
        var totalFiles: Int = 0

        // Aggregate the visited files by *per-app bucket* so each
        // ScanSubCategory corresponds to one owning app (or to the
        // generic category bucket if the path is system-wide).
        // The buckets are declared OUTSIDE the rootPath loop (Task 5 fix):
        // an app whose files appear under several of the category's
        // rootPaths must fold into ONE sub-category instead of one
        // duplicate row per rootPath (the "sparse / mis-grouped" scan
        // results complaint).
        var bucketByApp: [String: [ScanResult]] = [:]
        /// Per-app rule actions (level-3 grouping metadata) straight from
        /// the BundleIDResolver. Populated on the first sighting of a
        /// bucket key; action metadata is per-app, not per-path.
        var bucketActions: [String: [ResolvedApp.ResolvedAction]] = [:]
        var bucketSize: [String: Int64] = [:]
        var bucketTitle: [String: String] = [:]
        var bucketBundleID: [String: String] = [:]
        var bucketAppName: [String: String] = [:]

        for rootPath in def.paths {
            // Sandbox fix: `expandingTildeInPath` would expand `~` against
            // the container home under App Sandbox, making `~/Library/Caches`
            // silently point inside the app's container and the walk find
            // nothing. Resolve against the real home (libc passwd lookup)
            // before enumerating. `FileEnumerator` itself is shared with
            // kSift, so this stays here — orchestrator-level responsibility.
            let resolvedPath = UserPathResolver.expandTilde(rootPath)

            // F8: signpost marker around the FD-walk loop so an
            // Instruments run can attribute time to enumeration
            // (vs. classify / resolve / bucket folds).
            let _ = PerfInterval("scan.enumerate")

            for await info in await enumerator.enumerate(rootPath: resolvedPath) {
                if info.isDirectory { continue }   // Skip dirs — we count files

                await onProgress(ScanDelta(categoryID: def.id, filePath: info.path, bytesIncrement: info.size))

                let risk = classifier.classify(path: info.path)
                let app = await resolver.resolve(path: info.path)
                let bucketKey = app?.bundleID ?? Self.pseudoAppKey(for: def.id, rootPath: resolvedPath, filePath: info.path)

                let result = ScanResult(
                    url: URL(fileURLWithPath: info.path),
                    path: info.path,
                    title: (info.path as NSString).lastPathComponent,
                    fileSize: info.size,
                    modificationDate: info.modificationDate,
                    cleanType: .cache,
                    riskLevel: risk,
                    isRecommended: risk == .recommended
                )

                bucketByApp[bucketKey, default: []].append(result)
                bucketSize[bucketKey, default: 0] += info.size
                bucketTitle[bucketKey] = app?.nameCN ?? app?.name ?? def.title
                if let bundleID = app?.bundleID {
                    bucketBundleID[bucketKey] = bundleID
                    bucketAppName[bucketKey] = app?.nameCN ?? app?.name
                }
                if bucketActions[bucketKey] == nil {
                    bucketActions[bucketKey] = app?.actions ?? []
                }
                totalSize += info.size
                totalFiles += 1
            }
        }

        // Emit one ScanSubCategory per bucket. When there are no
        // results (the path didn't exist or FDA is missing), we
        // skip rather than emit an empty row — the UI shows a
        // placeholder via `totalSize == 0` instead.
        for (key, results) in bucketByApp where !results.isEmpty {
            let folderPrefix = "\(def.id).folder."
            if key.hasPrefix(folderPrefix) {
                // Pseudo-app bucket (Task B1): an unmatched top-level folder
                // becomes its own row titled with the REAL folder name.
                // Default OFF — `.caution` risk, isRecommended false.
                let folderName = String(key.dropFirst(folderPrefix.count))
                let sub = ScanSubCategory(
                    subCategoryID: key,
                    title: folderName,
                    bundleID: nil,
                    appName: folderName,
                    totalSize: bucketSize[key] ?? 0,
                    directResults: results,
                    showAction: false,
                    riskLevel: .caution,
                    isRecommended: false,
                    isPseudoApp: true
                )
                subItems.append(sub)
            } else if key == "\(def.id).unrecognized" {
                // Sentinel bucket (Task B1): files directly in the category
                // root with no app rule and no owning folder.
                let sub = ScanSubCategory(
                    subCategoryID: key,
                    title: "其他未识别",
                    bundleID: nil,
                    appName: nil,
                    totalSize: bucketSize[key] ?? 0,
                    directResults: results,
                    showAction: false,
                    riskLevel: def.riskLevel,
                    isRecommended: def.riskLevel == .recommended,
                    isPseudoApp: false
                )
                subItems.append(sub)
            } else if key == def.id {
                // Generic category bucket — defensive only; `pseudoAppKey`
                // now handles every non-app key so this branch is unreachable.
                let sub = ScanSubCategory(
                    subCategoryID: "\(def.id).\(key)",
                    title: bucketTitle[key] ?? def.title,
                    bundleID: bucketBundleID[key],
                    appName: bucketAppName[key],
                    totalSize: bucketSize[key] ?? 0,
                    directResults: results,
                    showAction: false,
                    riskLevel: def.riskLevel,
                    isRecommended: def.riskLevel == .recommended
                )
                subItems.append(sub)
            } else {
                // App-scoped bucket (unchanged, Task 5): build the level-3
                // action rows from the resolver's rule actions.
                let sub = ScanSubCategory(
                    subCategoryID: "\(def.id).\(key)",
                    title: bucketTitle[key] ?? def.title,
                    bundleID: key,
                    appName: bucketTitle[key],
                    totalSize: bucketSize[key] ?? 0,
                    actions: Self.buildActions(
                        for: key,
                        results: results,
                        def: def,
                        bucketActions: bucketActions,
                        bucketTitle: bucketTitle
                    ),
                    directResults: [],
                    showAction: true,
                    riskLevel: def.riskLevel,
                    isRecommended: def.riskLevel == .recommended
                )
                subItems.append(sub)
            }
        }

        let category = ScanCategory(
            categoryID: def.id,
            title: def.title,
            totalSize: totalSize,
            subItems: subItems,
            riskLevel: def.riskLevel,
            isRecommended: def.riskLevel == .recommended
        )

        return ScanOutcome(
            category: category,
            bytes: totalSize,
            fileCount: totalFiles,
            error: nil
        )
    }

    /// Build the level-3 `ScanAction` rows for one app-scoped bucket from
    /// the resolver's per-app rule actions (Task 5).
    ///
    /// A result belongs to an action when `result.path` is prefixed by one
    /// of the action's (tilde-expanded) paths; each result is assigned to
    /// the FIRST matching action — `ra.paths` order, then action order. An
    /// action is emitted only when it ends up with ≥1 result (no empty
    /// rows). Results that matched no rule path fold into ONE synthetic
    /// "other" action so nothing is orphaned under `showAction == true`
    /// (whose `children` ignores `directResults`).
    private static func buildActions(
        for bundleID: String,
        results: [ScanResult],
        def: CategoryDefinition,
        bucketActions: [String: [ResolvedApp.ResolvedAction]],
        bucketTitle: [String: String]
    ) -> [ScanAction] {
        let ruleActions = bucketActions[bundleID] ?? []
        var matched: [[ScanResult]] = Array(repeating: [], count: ruleActions.count)
        var unmatched: [ScanResult] = []

        for result in results {
            var assigned = false
            for (index, ruleAction) in ruleActions.enumerated() {
                for actionPath in ruleAction.paths {
                    let rawPath = UserPathResolver.expandTilde(actionPath)
                    let expandedPath = rawPath.count > 1 && rawPath.hasSuffix("/")
                        ? String(rawPath.dropLast()) : rawPath
                    if result.path == expandedPath || result.path.hasPrefix(expandedPath + "/") {
                        matched[index].append(result)
                        assigned = true
                        break
                    }
                }
                if assigned { break }
            }
            if !assigned { unmatched.append(result) }
        }

        var actions: [ScanAction] = []
        for (index, ruleAction) in ruleActions.enumerated() where !matched[index].isEmpty {
            actions.append(ScanAction(
                actionID: "\(def.id).\(bundleID).\(ruleAction.name)",
                actionType: .cache,
                title: ruleAction.nameCN,
                results: matched[index],
                recommend: true,
                riskLevel: def.riskLevel,
                isRecommended: true
            ))
        }
        if !unmatched.isEmpty {
            actions.append(ScanAction(
                actionID: "\(def.id).\(bundleID).other",
                actionType: .cache,
                title: bucketTitle[bundleID] ?? def.title,
                results: unmatched,
                recommend: true,
                riskLevel: def.riskLevel,
                isRecommended: true
            ))
        }
        return actions
    }

    // MARK: Helpers

    /// Computes the bucket key for a file no app rule matched (Task B1).
    /// - A file nested ≥2 levels under the category root folds into a
    ///   per-folder pseudo-app bucket keyed `"<categoryID>.folder.<leaf>"`.
    /// - A file sitting directly in the category root (or exactly on it)
    ///   folds into the sentinel bucket `"<categoryID>.unrecognized"`.
    private static func pseudoAppKey(for categoryID: String, rootPath: String, filePath: String) -> String {
        let root = rootPath.count > 1 && rootPath.hasSuffix("/")
            ? String(rootPath.dropLast()) : rootPath
        guard filePath == root || filePath.hasPrefix(root + "/") else {
            return "\(categoryID).unrecognized"
        }
        let remainder = String(filePath.dropFirst(root.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !remainder.isEmpty else { return "\(categoryID).unrecognized" }
        let parts = remainder.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count > 1 else { return "\(categoryID).unrecognized" }
        return "\(categoryID).folder.\(parts[0])"
    }

    /// Build the per-category progress rows shown in `ScanProgressView`.
    /// Static so it doesn't need actor isolation.
    private static func makeCategoryProgress(for def: CategoryDefinition) -> CategoryProgress {
        CategoryProgress(
            id: Self.stage(for: def.id)?.rawValue ?? 0,
            title: def.title,
            status: .pending,
            subCategories: [],
            filesFound: 0,
            totalSize: 0
        )
    }

    /// Map a `CategoryDefinition.id` to the corresponding `ScanStage`
    /// (1..8) so the 8-stage progress pill bar highlights the right
    /// stage as each category completes.
    private static func stage(for categoryID: String) -> ScanStage? {
        switch categoryID {
        case "system.cache":       return .cache
        case "developer.junk":     return .devJunk
        case "app.cache":          return .appLeftovers
        case "browser.junk":       return .browserCache
        case "mail.attachments":   return .iosCache      // reuses "data cache" stage
        case "system.logs":        return .binary         // generic fallback
        default:                   return nil
        }
    }
}

// MARK: - Category stream event

/// Single event yielded by `ScanOrchestrator.categoryStream()`. Either a
/// per-category payload (worker finished one category) or the terminal
/// snapshot (whole scan is done).
public enum ScanCategoryStreamEvent: Sendable {
    case category(ScanCategoryEvent)
    case terminal(ScanProgress)
}