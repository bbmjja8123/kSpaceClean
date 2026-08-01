// kSpaceClean/Features/SmartScan/Engine/ScanOrchestrator.swift
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
    /// kSpaceClean marketing copy ("系统缓存 / 应用缓存 / 上网垃圾 /
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
        let total = categoryDefs.count
        var completed = 0
        var totalBytes: Int64 = 0
        var totalFiles: Int = 0
        var failedCategories: [String] = []

        // Initial snapshot — UI shows total=6 immediately so the
        // progress ring can render even before the first Task returns.
        continuation.yield(ScanProgress(
            state: .scanning,
            filesDiscovered: 0,
            totalBytes: 0,
            currentDirectory: "",
            currentCategory: categoryDefs.first?.title ?? "",
            currentSubCategory: "",
            errors: [],
            finishedAt: nil,
            speed: .medium,
            categoryProgress: categoryDefs.map(Self.makeCategoryProgress),
            currentStage: Self.stage(for: categoryDefs.first?.id ?? "") ?? .cache
        ))

        await withTaskGroup(of: ScanOutcome.self) { group in
            for def in categoryDefs {
                group.addTask { [riskClassifier, bundleIDResolver, fileEnumerator] in
                    await Self.scanCategory(
                        def,
                        classifier: riskClassifier,
                        resolver: bundleIDResolver,
                        enumerator: fileEnumerator
                    )
                }
            }

            for await outcome in group {
                // Epoch guard: if a newer `startScan()` bumped the epoch
                // while this group was running, this scan is stale — stop
                // folding outcomes and let the fresh scan own the state.
                if Task.isCancelled || isCancelled || epoch != scanEpoch { break }
                completed += 1
                totalBytes += outcome.bytes
                totalFiles += outcome.fileCount
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

                continuation.yield(ScanProgress(
                    state: .scanning,
                    filesDiscovered: totalFiles,
                    totalBytes: totalBytes,
                    currentDirectory: "",
                    currentCategory: outcome.category.title,
                    currentSubCategory: "",
                    errors: [],
                    finishedAt: nil,
                    speed: .medium,
                    categoryProgress: [],
                    currentStage: Self.stage(for: outcome.category.categoryID) ?? .cache
                ))
            }
        }

        let terminalState: ScanProgress
        if Task.isCancelled || isCancelled {
            terminalState = ScanProgress(
                state: .cancelled,
                filesDiscovered: totalFiles,
                totalBytes: totalBytes,
                errors: [],
                finishedAt: Date(),
                speed: .medium
            )
        } else if !failedCategories.isEmpty {
            // Partial failure: surface the first error but still mark as
            // completed so the user can review what was found.
            terminalState = ScanProgress(
                state: .failed(failedCategories.first ?? "unknown"),
                filesDiscovered: totalFiles,
                totalBytes: totalBytes,
                errors: [],
                finishedAt: Date(),
                speed: .medium
            )
        } else {
            terminalState = ScanProgress(
                state: .completed,
                filesDiscovered: totalFiles,
                totalBytes: totalBytes,
                errors: [],
                finishedAt: Date(),
                speed: .medium
            )
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
        enumerator: FileEnumerator
    ) async -> ScanOutcome {
        var subItems: [ScanSubCategory] = []
        var totalSize: Int64 = 0
        var totalFiles: Int = 0

        for rootPath in def.paths {
            // Sandbox fix: `expandingTildeInPath` would expand `~` against
            // the container home under App Sandbox, making `~/Library/Caches`
            // silently point inside the app's container and the walk find
            // nothing. Resolve against the real home (libc passwd lookup)
            // before enumerating. `FileEnumerator` itself is shared with
            // kDupe, so this stays here — orchestrator-level responsibility.
            let resolvedPath = UserPathResolver.expandTilde(rootPath)

            // Aggregate the visited files by *per-app bucket* so each
            // ScanSubCategory corresponds to one owning app (or to the
            // generic category bucket if the path is system-wide).
            // F8: signpost marker around the FD-walk loop so an
            // Instruments run can attribute time to enumeration
            // (vs. classify / resolve / bucket folds).
            let _ = PerfInterval("scan.enumerate")
            var bucketByApp: [String: [ScanResult]] = [:]
            var bucketSize: [String: Int64] = [:]
            var bucketTitle: [String: String] = [:]
            var bucketBundleID: [String: String] = [:]
            var bucketAppName: [String: String] = [:]

            for await info in await enumerator.enumerate(rootPath: resolvedPath) {
                if info.isDirectory { continue }   // Skip dirs — we count files

                let risk = classifier.classify(path: info.path)
                let app = await resolver.resolve(path: info.path)
                let bucketKey = app?.bundleID ?? def.id

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
                totalSize += info.size
                totalFiles += 1
            }

            // Emit one ScanSubCategory per bucket. When there are no
            // results (the path didn't exist or FDA is missing), we
            // skip rather than emit an empty row — the UI shows a
            // placeholder via `totalSize == 0` instead.
            for (key, results) in bucketByApp where !results.isEmpty {
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

    // MARK: Helpers

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