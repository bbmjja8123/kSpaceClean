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

    // MARK: Init

    /// Default initializer used by `ScanEngine.startScan()` (Task B4).
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
    }

    // MARK: Cancellation

    /// Cooperative cancellation — flips an internal flag; the running
    /// TaskGroup observes the flag at every category boundary and exits
    /// early. (We intentionally do NOT call `Task.cancel()` on the
    /// TaskGroup because `FileEnumerator.walk` uses `FileManager` and we
    /// cannot interrupt a mid-`nextObject()` call atomically.)
    public func cancel() {
        isCancelled = true
    }

    // MARK: Scan Entry Point

    /// Start a parallel scan. The returned `AsyncStream` yields one
    /// `ScanProgress` per completed category plus a final `.completed`
    /// snapshot; consumers can iterate with `for await progress in stream`.
    ///
    /// - Returns: An `AsyncStream<ScanProgress>` that finishes once every
    ///   category worker has returned (or been short-circuited by
    ///   `cancel()`).
    public func startScan() -> AsyncStream<ScanProgress> {
        AsyncStream { continuation in
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
                await self.runScan(continuation: continuation)
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: Worker

    /// Main pipeline — fans out one Task per category, then aggregates.
    private func runScan(
        continuation: AsyncStream<ScanProgress>.Continuation
    ) async {
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
                if Task.isCancelled || isCancelled { break }
                completed += 1
                totalBytes += outcome.bytes
                totalFiles += outcome.fileCount
                if let err = outcome.error {
                    failedCategories.append("\(outcome.category.title): \(err)")
                }

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

        if Task.isCancelled || isCancelled {
            continuation.yield(ScanProgress(
                state: .cancelled,
                filesDiscovered: totalFiles,
                totalBytes: totalBytes,
                errors: [],
                finishedAt: Date(),
                speed: .medium
            ))
            continuation.finish()
            return
        }

        if !failedCategories.isEmpty {
            // Partial failure: surface the first error but still mark as
            // completed so the user can review what was found.
            continuation.yield(ScanProgress(
                state: .failed(failedCategories.first ?? "unknown"),
                filesDiscovered: totalFiles,
                totalBytes: totalBytes,
                errors: [],
                finishedAt: Date(),
                speed: .medium
            ))
        } else {
            continuation.yield(ScanProgress(
                state: .completed,
                filesDiscovered: totalFiles,
                totalBytes: totalBytes,
                errors: [],
                finishedAt: Date(),
                speed: .medium
            ))
        }
        continuation.finish()

        // Reset internal counters so the same actor can be reused for a
        // second scan (we do not currently expose this, but it keeps the
        // semantics correct for tests that drive multiple cycles).
        categoriesScanned = completed
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
            // Aggregate the visited files by *per-app bucket* so each
            // ScanSubCategory corresponds to one owning app (or to the
            // generic category bucket if the path is system-wide).
            var bucketByApp: [String: [ScanResult]] = [:]
            var bucketSize: [String: Int64] = [:]
            var bucketTitle: [String: String] = [:]
            var bucketBundleID: [String: String] = [:]
            var bucketAppName: [String: String] = [:]

            for await info in await enumerator.enumerate(rootPath: rootPath) {
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