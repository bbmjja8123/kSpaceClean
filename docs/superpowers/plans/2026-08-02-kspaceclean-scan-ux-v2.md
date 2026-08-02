# kSpaceClean Scan UX v2 — Live Progress + Pseudo-App Splitting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the two scan-flow complaints — (1) scan progress has no live estimate, no animation, no ETA; (2) 4-level results are broken because unmatched files collapse into one generic "应用缓存" bucket instead of real app rows — by adding a live progress composer (real-time ring/ETA/current-file) and splitting unmatched top-level folders into pseudo-app rows, plus growing the rule library 108 → 151.

**Architecture:**
- **Live progress (A):** `ScanOrchestrator` (actor) gains a composer: per-file `ScanDelta` events flow from each category worker into throttled `ScanProgress` snapshots carrying `stats.filesPerSecond`, `currentNodePath`, and seeded/updated `categoryProgress` rows. `ScanProgressMath` (pure static enum) computes a 3-signal completion fraction (categories 60% + inflight 25% + stats 15%) and an ETA. `ScanProgressView` swaps its hand-rolled `progressFraction` for `ScanProgressMath` and adds a 预计剩余 stat column.
- **Pseudo-app splitting (B):** when no app rule matches a file, `bucketKey` is derived from the REAL top-level folder under the category root (`<categoryID>.folder.<leaf>`), so each unmatched folder renders as its own row titled with the folder name; files directly in the category root fold into one sentinel "其他未识别" bucket. Pseudo-app rows are `.caution` risk, off-by-default, and exempt from the small-file fold. The rule library grows by 43 user-installed apps to close the attribution gap.

**Tech Stack:** Swift 5.8 (Xcode 14.3, macOS 13 SDK), SwiftUI, Swift Concurrency (async/await + TaskGroup + AsyncStream), XCTest.

## Global Constraints

- **Toolchain:** Build with `DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer"`. Xcode 14.3 / Swift 5.8 / macOS 13 SDK. **Forbidden SDK APIs:** `.symbolEffect(...)` (any), `AsyncStream.makeStream(of:)`. Do not re-add `.symbolEffect` anywhere (the `pulseIcon` helper was deliberately stripped of it).
- **Strict concurrency:** project sets `SWIFT_STRICT_CONCURRENCY = complete`. All new `@Sendable` closures must have explicit captures; all new streamed types must conform to `Sendable`.
- **Type facts (verbatim, do not contradict):**
  - `ScanProgress.speed` is `ScanSpeed`, **not** Double → `composeSnapshot` passes `speed: .medium`.
  - `ScanItemStatus` has EXACTLY 4 cases: `pending, scanning, completed, failed`.
  - `ScanStats` memberwise init order: `(discoveredSize: Int64 = 0, fileCount: Int = 0, elapsed: TimeInterval = 0, filesPerSecond: Double = 0)`.
  - `ScanProgress` memberwise init order: `state, filesDiscovered, totalBytes, currentDirectory, currentSubCategory, errors, finishedAt, speed, categoryProgress, currentStage, currentNodePath, stats` — but every existing call site omits trailing defaults; follow the existing call-site style (`state:`, `finishedAt:`, then defaults).
  - `CategoryProgress` memberwise init: `(id: Int, title: String, status: ScanItemStatus, subCategories: [SubCategoryProgress], filesFound: Int, totalSize: Int64)`; `id`/`title` are `let`.
  - `ScanOutcome` is `private struct ScanOutcome: Sendable { let category: ScanCategory; let bytes: Int64; let fileCount: Int; let error: String? }`.
  - `ScanOrchestrator` init: `init(categoryDefinitions: [CategoryDefinition] = CategoryDefinition.defaults, riskClassifier: RiskClassifier = RiskClassifier(), bundleIDResolver: BundleIDResolver = BundleIDResolver(), fileEnumerator: FileEnumerator = FileEnumerator())`. **Tests must construct with `ScanOrchestrator(categoryDefinitions: cats)`, never `ScanOrchestrator()`.**
  - `makeCategoryProgress(_ def: CategoryDefinition)` takes a **CategoryDefinition** (not a ScanCategory). Live composer updates use seeded-dict lookup (`liveCategoryProgress[def.id]`), never `makeCategoryProgress(outcome.category)`.
- **Cascade risk gate — DO NOT CHANGE:** `ScanSubCategory.setState` already gates per-child auto-select on `child.riskLevel.defaultChecked` (ScanSubCategory.swift:99/112). No edit to `setState` in this plan. `RiskLevel.defaultChecked` is `self == .recommended`.
- **Do not restructure existing behavior:** `buildActions` boundary-safe match (ScanOrchestrator.swift:712-721) already strips trailing slashes — leave it. Legacy scan pipeline untouched.
- **Test additions are append-only** to these existing files (do NOT create new test files, do NOT modify existing tests): `kSpaceClean/Tests/ScanOrchestratorIntegrationTests.swift`, `kSpaceClean/Tests/ScanProgressTests.swift`, `kSpaceClean/Tests/ScanTreeFilterTests.swift`, `kSpaceClean/Tests/AppRuleFixtures.swift`.
- **Baseline:** 268 tests passing. After this plan: **284 passing** (A1: 2, A2: 8, B1: 2, B2: 2, B3: 2). Zero build warnings.
- **Test command (verbatim):**
  ```bash
  cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" /Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild -project kSpaceClean/kSpaceClean.xcodeproj -scheme kSpaceClean -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO ONLY_ACTIVE_ARCH=YES test
  ```
- **Rule library (`kSpaceClean/Resources/bundleIDMapping.json`) invariants:** header keys `version` (2), `generatedAt`, `source`, `appCount`, `apps`. `appCount` MUST equal the real `apps` dict count. Entry schema: dict key == `bundleID`; entry fields `bundleID`, `appstoreBundleID` (**must be JSON `null`**), `nameCN`, `name`, `actions[]` (each with `nameCN`, `name`, `type`, `paths[]`), `vendor`, `type`, `riskLevel`, `confidence`. New entries: `"riskLevel": "caution"`, `"confidence": "medium"`, action type `"appcache"` (or `"file"` for Logs). **NEVER** declare a cleanable action at a bare user-data root: `~/Library/Application Support/<Leaf>/` (model/chat/db store) or `~/Library/Containers/<Bundle>/Data` (container home). Cache/log subdirs only.
- **JSON validity** must be verified after every edit: `python3 -c "import json; json.load(open('kSpaceClean/Resources/bundleIDMapping.json'))"`.
- **Commit style:** `feat(kSpaceClean): <imperative summary>`.
- **SDD artifact filenames:** task briefs/reports for THIS plan go to `.superpowers/sdd/` with names `2026-08-02-scan-ux-v2-task-N-{brief,report}.md` — the stale kDupe `task-A1-brief.md` etc. already exist and must not be reused.

---

## File Structure

| File | Responsibility | Touched by |
|---|---|---|
| `kSpaceClean/Features/SmartScan/ScanProgress.swift` | `ScanDelta` (append after `ScanStats`), `ScanProgressMath` (append at end) | A1, A2 |
| `kSpaceClean/Features/SmartScan/Engine/ScanOrchestrator.swift` | Live progress composer (state, seeding, wiring, `composeSnapshot`, `recordProgress`, `markCategoryCompleted`, `yieldSnapshot`); pseudo-app bucket key + 3-way emit branch; `pseudoAppKey` helper | A1, B1 |
| `kSpaceClean/Features/SmartScan/Views/ScanProgressView.swift` | Ring fraction via `ScanProgressMath`, 预计剩余 stat column, `etaText` | A2 |
| `kSpaceClean/Features/SmartScan/Models/ScanSubCategory.swift` | `isPseudoApp` property + init param | B1 |
| `kSpaceClean/Features/SmartScan/Views/ScanResultsViewModel.swift` | `annotateSubHidden` pseudo-app fold exemption | B2 |
| `kSpaceClean/Resources/bundleIDMapping.json` | `appCount` 108 → 151 + 43 new entries | B3 |
| `kSpaceClean/Tests/ScanOrchestratorIntegrationTests.swift` | Append `ScanProgressComposerTests` (A1), `ScanPseudoAppSplittingTests` (B1) | A1, B1 |
| `kSpaceClean/Tests/ScanProgressTests.swift` | Append `ScanProgressMathTests` (A2) | A2 |
| `kSpaceClean/Tests/ScanTreeFilterTests.swift` | Append `PseudoAppFilterExemptionTests` (B2) | B2 |
| `kSpaceClean/Tests/AppRuleFixtures.swift` | `task12BundleIDs` + presence/guard tests in `AppRuleLibraryAudit` (B3) | B3 |

### Task A1: Live progress composer

**Files:**
- Modify: `kSpaceClean/Features/SmartScan/ScanProgress.swift` (append `ScanDelta` after line 118)
- Modify: `kSpaceClean/Features/SmartScan/Engine/ScanOrchestrator.swift`
- Test: `kSpaceClean/Tests/ScanOrchestratorIntegrationTests.swift` (append `ScanProgressComposerTests`)

**Interfaces:**
- Consumes: existing `ScanProgress`, `CategoryProgress`, `ScanStats`, `ScanItemStatus`, `ScanOutcome`, `CategoryDefinition`.
- Produces: `ScanDelta` struct (public, Sendable); actor state + `recordProgress`/`markCategoryCompleted`/`yieldSnapshot`/`composeSnapshot`; `scanCategory` gains `onProgress: (ScanDelta) async -> Void` param. Consumed by A2 (`stats.filesPerSecond`, `currentNodePath`, `categoryProgress` in every snapshot).

- [ ] **Step 1: Write the failing tests**

Append this class to the END of `kSpaceClean/Tests/ScanOrchestratorIntegrationTests.swift` (it already has `import XCTest`, `import FileScanner`, `@testable import kSpaceClean`):

```swift
/// Task A1 — live progress composer. Drives a scan over a 5000-file fixture
/// and asserts the interim `.scanning` snapshots carry real-time stats
/// (the complaint: the ring froze near 0 until the final yield).
@MainActor
final class ScanProgressComposerTests: XCTestCase {
    private var a1Root: URL!
    private var cachesRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        let root = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("sclean-a1-progress-\(UUID().uuidString)", isDirectory: true)
        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        for i in 0..<5000 {
            try Data(repeating: 0x01, count: 256)
                .write(to: caches.appendingPathComponent("f\(i).bin"))
        }
        a1Root = root
        cachesRoot = caches
    }

    override func tearDown() async throws {
        if let root = a1Root {
            try? FileManager.default.removeItem(at: root)
        }
        try await super.tearDown()
    }

    private func scanToCompletion(_ orchestrator: ScanOrchestrator) async -> [ScanProgress] {
        let stream = await orchestrator.startScan()
        var snapshots: [ScanProgress] = []
        for await p in stream {
            snapshots.append(p)
            if case .completed = p.state { break }
            if case .failed(let err) = p.state { XCTFail("scan failed: \(err)") }
        }
        return snapshots
    }

    func testInterimScanningSnapshotAndTerminalCompletion() async throws {
        let cats = [
            CategoryDefinition(
                id: "app.cache",
                title: "App Cache",
                paths: [cachesRoot.path],
                riskLevel: .caution
            )
        ]
        let orchestrator = ScanOrchestrator(categoryDefinitions: cats)
        let snapshots = await scanToCompletion(orchestrator)

        let first = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(first.state, .scanning,
                       "first snapshot must be a live .scanning state, not idle")

        // Complaint #1 regression: at least one interim snapshot must carry
        // real-time stats (file count > 0, live current path) so the ring
        // and the stats row move continuously, not only at the end.
        let interimSnapshot = try XCTUnwrap(
            snapshots.first { $0.state == .scanning && $0.stats.fileCount > 0 },
            "interim scanning snapshot with real-time stats required"
        )
        XCTAssertFalse(interimSnapshot.currentNodePath?.isEmpty ?? true,
                       "interim snapshot must carry the currently-scanned file path")
        XCTAssertEqual(interimSnapshot.categoryProgress.count, 1,
                       "interim snapshot must carry the seeded per-category rows")

        let final = try XCTUnwrap(snapshots.last)
        XCTAssertEqual(final.state, .completed)
        let row = try XCTUnwrap(final.categoryProgress.first)
        XCTAssertEqual(row.status, .completed)
        XCTAssertEqual(row.filesFound, 5000)
        XCTAssertEqual(row.totalSize, 1_280_000)
        XCTAssertEqual(final.stats.fileCount, 5000)
        XCTAssertGreaterThan(final.stats.elapsed, 0)
        XCTAssertGreaterThan(final.stats.filesPerSecond, 0)
    }

    func testProgressStreamStartsWithPendingRowsSeeded() async throws {
        let emptyA = a1Root.appendingPathComponent("EmptyA", isDirectory: true)
        let emptyB = a1Root.appendingPathComponent("EmptyB", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: emptyB, withIntermediateDirectories: true)
        let cats = [
            CategoryDefinition(id: "system.cache", title: "System Cache", paths: [emptyA.path], riskLevel: .recommended),
            CategoryDefinition(id: "system.logs", title: "System Logs", paths: [emptyB.path], riskLevel: .recommended),
        ]
        let orchestrator = ScanOrchestrator(categoryDefinitions: cats)
        let snapshots = await scanToCompletion(orchestrator)

        let first = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(first.categoryProgress.count, 2,
                       "first snapshot must seed one pending row per category")
        XCTAssertTrue(first.categoryProgress.allSatisfy { $0.status == .pending })

        let final = try XCTUnwrap(snapshots.last)
        XCTAssertEqual(final.categoryProgress.count, 2)
        XCTAssertTrue(final.categoryProgress.allSatisfy { $0.status == .completed },
                      "terminal snapshot must force-complete every row so the ring reaches 100%")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (filtered):
```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" /Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild -project kSpaceClean/kSpaceClean.xcodeproj -scheme kSpaceClean -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO ONLY_ACTIVE_ARCH=YES -only-testing:kSpaceCleanTests/ScanProgressComposerTests test
```
Expected: FAIL — `interim scanning snapshot with real-time stats required` (current interim yields carry `stats` defaulted to zero; `currentNodePath` never set), and `final.stats.fileCount == 0`.

- [ ] **Step 3: Add `ScanDelta` to `ScanProgress.swift`**

Append after the `ScanStats` struct (end of file, line 118):

```swift
/// One incremental file-discovery event emitted by a category worker.
/// Consumed by the orchestrator's live progress composer (Task A1) so the
/// progress ring / stats move continuously instead of only at category
/// boundaries.
public struct ScanDelta: Sendable {
    public let categoryID: String
    public let filePath: String
    public let bytesIncrement: Int64
    public let filesIncrement: Int

    public init(categoryID: String, filePath: String, bytesIncrement: Int64, filesIncrement: Int = 1) {
        self.categoryID = categoryID
        self.filePath = filePath
        self.bytesIncrement = bytesIncrement
        self.filesIncrement = filesIncrement
    }
}
```

- [ ] **Step 4: Add composer state to `ScanOrchestrator`**

In `ScanOrchestrator.swift`, immediately after the `finalTerminalState` property (line 194), add:

```swift
    // MARK: Live progress composer (Task A1)
    private var liveCategoryProgress: [String: CategoryProgress] = [:]
    private var runningFiles: Int = 0
    private var runningBytes: Int64 = 0
    private var scanStartedAt: Date = Date()
    private var currentNodePath: String?
    private var currentCategoryID: String = ""
    private var lastYieldAt: Date = .distantPast
    private var activeProgressContinuation: AsyncStream<ScanProgress>.Continuation?
```

- [ ] **Step 5: Seed composer state in `startScan`**

In `startScan()`, immediately after the `finalTerminalState = ScanProgress(...)` reset block (after line 296), add:

```swift
        // Seed the live composer for this scan (Task A1). Row order follows
        // `categoryDefs` and is preserved by every `composeSnapshot`.
        liveCategoryProgress = Dictionary(
            uniqueKeysWithValues: categoryDefs.map { ($0.id, Self.makeCategoryProgress($0)) }
        )
        runningFiles = 0
        runningBytes = 0
        scanStartedAt = Date()
        currentNodePath = nil
        currentCategoryID = categoryDefs.first?.id ?? ""
        lastYieldAt = .distantPast
        activeProgressContinuation = nil
```

- [ ] **Step 6: Rewire `runScan`**

In `runScan`:
1. After `let _ = PerfInterval("scan.orchestrate")` (line 326) add:
   ```swift
   activeProgressContinuation = continuation
   defer { activeProgressContinuation = nil }
   ```
2. DELETE the dead locals `let total = categoryDefs.count` (line 327), `var totalBytes: Int64 = 0` (line 329), `var totalFiles: Int = 0` (line 330). KEEP `var completed = 0` (line 328) and `var failedCategories: [String] = []` (line 331).
3. Replace the initial yield (lines 335-347) with:
   ```swift
   continuation.yield(composeSnapshot(state: .scanning))
   ```
4. Replace the `group.addTask` block (lines 351-358) with (adds `weak self` capture + `onProgress` wiring; keep `[riskClassifier, bundleIDResolver, fileEnumerator]` too):
   ```swift
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
   ```
5. In the fold loop (`for await outcome in group`), DELETE `totalBytes += outcome.bytes` (line 367) and `totalFiles += outcome.fileCount` (line 368). After the `pendingCategoryEvents.append(...)` block (line 376-380) add:
   ```swift
   await markCategoryCompleted(outcome, epoch: epoch)
   continuation.yield(composeSnapshot(state: .scanning))
   ```
   then DELETE the old per-category `continuation.yield(ScanProgress(... categoryProgress: [] ...))` block (lines 382-394).
6. Replace the three partial terminal inits (lines 398-428) with:
   ```swift
   let terminalState: ScanProgress
   if Task.isCancelled || isCancelled {
       terminalState = composeSnapshot(state: .cancelled, finishedAt: Date())
   } else if !failedCategories.isEmpty {
       terminalState = composeSnapshot(
           state: .failed(failedCategories.first ?? "unknown"),
           finishedAt: Date()
       )
   } else {
       terminalState = composeSnapshot(state: .completed, finishedAt: Date())
   }
   ```
   (Keep the `guard epoch == scanEpoch else { continuation.finish(); return }` and the `finalTerminalState = terminalState` / `hasFinishedScan = true` / `continuation.yield(terminalState)` / `continuation.finish()` block untouched below it.)

- [ ] **Step 7: Add the composer methods**

Insert a new `// MARK: - Live progress composer (Task A1)` section immediately BEFORE `// MARK: - Category stream (C2)` (line 451):

```swift
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
            currentCategory: currentCategoryID,
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
```

- [ ] **Step 8: Thread `onProgress` through `scanCategory`**

Change the `scanCategory` signature (line 549-554) to add the last parameter:

```swift
    private static func scanCategory(
        _ def: CategoryDefinition,
        classifier: RiskClassifier,
        resolver: BundleIDResolver,
        enumerator: FileEnumerator,
        onProgress: (ScanDelta) async -> Void
    ) async -> ScanOutcome {
```

Inside the `for await info in await enumerator.enumerate(rootPath: resolvedPath)` loop, immediately after `if info.isDirectory { continue }` (line 592), add:

```swift
                await onProgress(ScanDelta(categoryID: def.id, filePath: info.path, bytesIncrement: info.size))
```

- [ ] **Step 9: Run the tests to verify they pass**

Same `-only-testing:kSpaceCleanTests/ScanProgressComposerTests` command. Expected: 2/2 PASS.

- [ ] **Step 10: Run the full suite**

Run the full test command (Global Constraints). Expected: 270 passing (268 baseline + 2 A1).

- [ ] **Step 11: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && git add kSpaceClean/Features/SmartScan/ScanProgress.swift kSpaceClean/Features/SmartScan/Engine/ScanOrchestrator.swift kSpaceClean/Tests/ScanOrchestratorIntegrationTests.swift && git commit -m "feat(kSpaceClean): add live scan-progress composer with per-file deltas"
```

### Task A2: Progress math + ring/ETA UI

**Files:**
- Modify: `kSpaceClean/Features/SmartScan/ScanProgress.swift` (append `ScanProgressMath` at end)
- Modify: `kSpaceClean/Features/SmartScan/Views/ScanProgressView.swift`
- Test: `kSpaceClean/Tests/ScanProgressTests.swift` (append `ScanProgressMathTests`)

**Interfaces:**
- Consumes: `ScanProgressMath` (A2 defines it), `progress.stats.filesPerSecond` / `categoryProgress` / `state` from A1 snapshots.
- Produces: `ScanProgressMath.completionFraction(categoryProgress:stats:) -> Double`, `estimatedRemainingSeconds(categoryProgress:stats:) -> TimeInterval?`, `formatClock(_:) -> String`; `ScanProgressView.progressFraction` and `etaText`.

- [ ] **Step 1: Write the failing tests**

Append to the END of `kSpaceClean/Tests/ScanProgressTests.swift`:

```swift
final class ScanProgressMathTests: XCTestCase {
    private func row(id: Int, status: ScanItemStatus) -> CategoryProgress {
        CategoryProgress(id: id, title: "\(id)", status: status,
                         subCategories: [], filesFound: 0, totalSize: 0)
    }

    func testCompletionEmptyProgressIsZero() {
        XCTAssertEqual(
            ScanProgressMath.completionFraction(categoryProgress: [], stats: ScanStats()),
            0
        )
    }

    func testCompletionAllDoneIsOne() {
        let rows = [row(id: 1, status: .completed), row(id: 2, status: .completed)]
        XCTAssertEqual(
            ScanProgressMath.completionFraction(categoryProgress: rows, stats: ScanStats()),
            1.0,
            "all categories done must hit exactly 100% so the ring never wedges short"
        )
    }

    func testCompletionBlendsStatsAndInflight() {
        let rows = [row(id: 1, status: .completed), row(id: 2, status: .scanning)]
        let stats = ScanStats(discoveredSize: 0, fileCount: 5000, elapsed: 100, filesPerSecond: 50)
        let fraction = ScanProgressMath.completionFraction(categoryProgress: rows, stats: stats)
        XCTAssertGreaterThan(fraction, 0.3)
        XCTAssertLessThan(fraction, 1.0)
    }

    func testCompletionNeverExceedsOne() {
        let rows = [row(id: 1, status: .completed)]
        let stats = ScanStats(discoveredSize: 0, fileCount: 100_000, elapsed: 1, filesPerSecond: 1000)
        XCTAssertLessThanOrEqual(
            ScanProgressMath.completionFraction(categoryProgress: rows, stats: stats),
            1.0
        )
    }

    func testETAEarlyFractionReturnsNil() {
        XCTAssertNil(
            ScanProgressMath.estimatedRemainingSeconds(categoryProgress: [], stats: ScanStats())
        )
    }

    func testETAStallReturnsNil() {
        let rows = [row(id: 1, status: .completed), row(id: 2, status: .pending)]
        XCTAssertNil(
            ScanProgressMath.estimatedRemainingSeconds(
                categoryProgress: rows,
                stats: ScanStats(discoveredSize: 0, fileCount: 0, elapsed: 10, filesPerSecond: 0)
            ),
            "a stalled scan (0 files/sec) must not show a fake ETA"
        )
    }

    func testETAComputesRemaining() {
        let rows = [row(id: 1, status: .completed), row(id: 2, status: .scanning)]
        let stats = ScanStats(discoveredSize: 0, fileCount: 100, elapsed: 10, filesPerSecond: 10)
        let eta = try! XCTUnwrap(
            ScanProgressMath.estimatedRemainingSeconds(categoryProgress: rows, stats: stats)
        )
        XCTAssertGreaterThan(eta, 0)
    }

    func testFormatClock() {
        XCTAssertEqual(ScanProgressMath.formatClock(42), "0:42")
        XCTAssertEqual(ScanProgressMath.formatClock(65), "1:05")
        XCTAssertEqual(ScanProgressMath.formatClock(3600), "1:00:00")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" /Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild -project kSpaceClean/kSpaceClean.xcodeproj -scheme kSpaceClean -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO ONLY_ACTIVE_ARCH=YES -only-testing:kSpaceCleanTests/ScanProgressMathTests test
```
Expected: FAIL — `ScanProgressMath` is not defined.

- [ ] **Step 3: Add `ScanProgressMath` to `ScanProgress.swift`**

Append at the END of `ScanProgress.swift` (after `ScanStats` / `ScanDelta`):

```swift
/// Pure math for the progress ring / ETA (Task A2). Kept as a static enum
/// so the UI and tests share one implementation with no hidden state.
public enum ScanProgressMath {
    /// Above this many in-flight files the scan is "well into" a category and
    /// the inflight ratio stops dominating the ring.
    public static let inflightFileTarget = 3_000
    /// Expected total file count used to scale the stats-based component.
    public static let statsFileTarget = 20_000

    /// 0...1 completion estimate. Combines three signals so the ring moves
    /// continuously instead of freezing between category boundaries:
    /// - 60%: fraction of categories completed
    /// - 25%: files discovered so far vs `inflightFileTarget` (bounded)
    /// - 15%: stats fileCount vs `statsFileTarget` (bounded)
    public static func completionFraction(
        categoryProgress: [CategoryProgress],
        stats: ScanStats
    ) -> Double {
        let total = categoryProgress.count
        guard total > 0 else { return 0 }
        let done = categoryProgress.filter { $0.status == .completed }.count
        if done == total { return 1.0 }
        let categoryRatio = Double(done) / Double(total)
        let inflightRatio = min(Double(stats.fileCount) / Double(inflightFileTarget), 1)
        let statsRatio = min(Double(stats.fileCount) / Double(statsFileTarget), 1)
        return min(categoryRatio * 0.6 + inflightRatio * 0.25 + statsRatio * 0.15, 1)
    }

    /// Estimated seconds remaining, or `nil` when there is not enough signal
    /// (early scan, stalled speed, or already complete).
    public static func estimatedRemainingSeconds(
        categoryProgress: [CategoryProgress],
        stats: ScanStats
    ) -> TimeInterval? {
        let fraction = completionFraction(categoryProgress: categoryProgress, stats: stats)
        guard fraction >= 0.03, fraction <= 0.999 else { return nil }
        guard stats.filesPerSecond > 0, stats.fileCount > 0 else { return nil }
        let remainingFraction = 1.0 - fraction
        let remainingFiles = Double(stats.fileCount) / fraction * remainingFraction
        return remainingFiles / stats.filesPerSecond
    }

    /// Formats seconds as `m:ss` or `h:mm:ss`.
    public static func formatClock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
```

- [ ] **Step 4: Wire the ring + ETA into `ScanProgressView`**

In `ScanProgressView.swift`:
1. Replace the whole `progressFraction` computed property (lines 219-232) with:
   ```swift
   /// Fractional completion via `ScanProgressMath` (Task A2) — categories
   /// completed + in-flight files + stats so the ring moves continuously
   /// instead of freezing between category boundaries.
   private var progressFraction: Double {
       ScanProgressMath.completionFraction(
           categoryProgress: progress.categoryProgress,
           stats: progress.stats
       )
   }
   ```
2. In `statsRow` (lines 121-148), after the 速度 `statColumn` and before the closing brace of the `HStack`, add:
   ```swift

            divider

            statColumn(
                title: "预计剩余",
                value: etaText,
                caption: ""
            )
   ```
3. Add `etaText` immediately after the new `progressFraction` property:
   ```swift
   /// Live ETA string; shows "—" until the math has enough signal.
   private var etaText: String {
       if case .scanning = progress.state {
           if let eta = ScanProgressMath.estimatedRemainingSeconds(
               categoryProgress: progress.categoryProgress,
               stats: progress.stats
           ) {
               return ScanProgressMath.formatClock(eta)
           }
       }
       return "—"
   }
   ```

- [ ] **Step 5: Run the tests to verify they pass**

Same `-only-testing:kSpaceCleanTests/ScanProgressMathTests` command. Expected: 8/8 PASS.

- [ ] **Step 6: Run the full suite**

Full test command. Expected: 278 passing (270 + 8 A2).

- [ ] **Step 7: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && git add kSpaceClean/Features/SmartScan/ScanProgress.swift kSpaceClean/Features/SmartScan/Views/ScanProgressView.swift kSpaceClean/Tests/ScanProgressTests.swift && git commit -m "feat(kSpaceClean): add progress ring math and live ETA column"
```

### Task B1: Pseudo-app splitting for unmatched folders

**Files:**
- Modify: `kSpaceClean/Features/SmartScan/Models/ScanSubCategory.swift`
- Modify: `kSpaceClean/Features/SmartScan/Engine/ScanOrchestrator.swift`
- Test: `kSpaceClean/Tests/ScanOrchestratorIntegrationTests.swift` (append `ScanPseudoAppSplittingTests`)

**Interfaces:**
- Consumes: `bucketByApp`/`bucketSize` aggregation, `pseudoAppKey` (B1 defines), `ScanSubCategory` init.
- Produces: `ScanSubCategory.isPseudoApp` (let, default false) + init param; bucket keys `"<categoryID>.folder.<leaf>"` and `"<categoryID>.unrecognized"`; pseudo-app/sentinel subs. Consumed by B2 (`isPseudoApp` + `totalSize`).

- [ ] **Step 1: Write the failing tests**

Append to the END of `kSpaceClean/Tests/ScanOrchestratorIntegrationTests.swift`:

```swift
/// Task B1 — pseudo-app splitting. Unmatched top-level folders become their
/// own rows titled with the REAL folder name; files directly in the category
/// root fold into the "其他未识别" sentinel.
@MainActor
final class ScanPseudoAppSplittingTests: XCTestCase {
    private func scanOneCategory(_ categoryRoot: URL) async -> ScanCategory {
        let cats = [
            CategoryDefinition(
                id: "app.cache",
                title: "App Cache",
                paths: [categoryRoot.path],
                riskLevel: .caution
            )
        ]
        let orchestrator = ScanOrchestrator(categoryDefinitions: cats)
        let stream = await orchestrator.startScan()
        var emitted: [ScanCategory] = []
        let consumer = Task { @MainActor in
            for await event in await orchestrator.categoryStream() {
                if case .category(let catEvent) = event {
                    emitted.append(catEvent.category)
                }
            }
        }
        for await p in stream {
            if case .completed = p.state { break }
            if case .failed(let err) = p.state { XCTFail("scan failed: \(err)") }
        }
        await consumer.value
        return try! XCTUnwrap(emitted.first, "scan must emit exactly one category")
    }

    func testUnmatchedTopLevelFolderBecomesPseudoAppRow() async throws {
        let root = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("sclean-b1-pseudo-\(UUID().uuidString)", isDirectory: true)
        let categoryRoot = root.appendingPathComponent("AppCache", isDirectory: true)
        let appDir = categoryRoot.appendingPathComponent("SomeRandomApp", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0xAB, count: 256).write(to: appDir.appendingPathComponent("cache.bin"))

        let category = await scanOneCategory(categoryRoot)
        let sub = try XCTUnwrap(category.subItems.first)
        XCTAssertTrue(sub.isPseudoApp,
                      "unmatched top-level folder must become a pseudo-app row")
        XCTAssertEqual(sub.title, "SomeRandomApp",
                       "pseudo-app row must be titled with the REAL folder name")
        XCTAssertFalse(sub.showAction)
        XCTAssertEqual(sub.directResults.count, 1)
        XCTAssertEqual(sub.riskLevel, .caution)
        XCTAssertFalse(sub.isRecommended,
                       "pseudo-app rows must be off-by-default, never auto-selected")
    }

    func testUnrecognizedRootFilesGoToSentinelSub() async throws {
        let root = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("sclean-b1-sentinel-\(UUID().uuidString)", isDirectory: true)
        let categoryRoot = root.appendingPathComponent("AppCache", isDirectory: true)
        try FileManager.default.createDirectory(at: categoryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0xCD, count: 128).write(to: categoryRoot.appendingPathComponent("stray.bin"))

        let category = await scanOneCategory(categoryRoot)
        let sub = try XCTUnwrap(category.subItems.first)
        XCTAssertEqual(sub.title, "其他未识别")
        XCTAssertEqual(sub.directResults.count, 1)
        XCTAssertFalse(sub.isPseudoApp)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" /Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild -project kSpaceClean/kSpaceClean.xcodeproj -scheme kSpaceClean -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO ONLY_ACTIVE_ARCH=YES -only-testing:kSpaceCleanTests/ScanPseudoAppSplittingTests test
```
Expected: FAIL — `isPseudoApp` does not exist; unmatched files collapse into one generic bucket titled "App Cache" instead of "SomeRandomApp".

- [ ] **Step 3: Add `isPseudoApp` to `ScanSubCategory`**

In `ScanSubCategory.swift`, add after line 33 (`public var isHiddenByFilter: Bool = false`):

```swift
    /// True when this sub-category is a synthesized "pseudo-app" row for an
    /// unmatched top-level folder (Task B1). Pseudo-app rows are always
    /// `.caution` risk (never auto-selected) and exempt from the small-file
    /// fold (see `ScanResultsViewModel.annotateSubHidden`).
    public let isPseudoApp: Bool
```

In the init (lines 42-58), insert `isPseudoApp: Bool = false,` between `isRecommended: Bool = true,` and `isHiddenByFilter: Bool = false`; add `self.isPseudoApp = isPseudoApp` assignment after `self.isRecommended = isRecommended`.

- [ ] **Step 4: Add the `pseudoAppKey` helper to `ScanOrchestrator`**

Insert before `makeCategoryProgress` in the `// MARK: Helpers` section:

```swift
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
```

- [ ] **Step 5: Change the bucket key in `scanCategory`**

Replace line 596:

```swift
                let bucketKey = app?.bundleID ?? def.id
```

with:

```swift
                let bucketKey = app?.bundleID ?? Self.pseudoAppKey(for: def.id, rootPath: resolvedPath, filePath: info.path)
```

- [ ] **Step 6: Replace the emit branch with the 3-way branch**

Replace the whole `for (key, results) in bucketByApp where !results.isEmpty { ... }` block (lines 628-669) with:

```swift
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
```

- [ ] **Step 7: Run the tests to verify they pass**

Same `-only-testing:kSpaceCleanTests/ScanPseudoAppSplittingTests` command. Expected: 2/2 PASS.

- [ ] **Step 8: Run the full suite**

Full test command. Expected: 280 passing (278 + 2 B1).

- [ ] **Step 9: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && git add kSpaceClean/Features/SmartScan/Models/ScanSubCategory.swift kSpaceClean/Features/SmartScan/Engine/ScanOrchestrator.swift kSpaceClean/Tests/ScanOrchestratorIntegrationTests.swift && git commit -m "feat(kSpaceClean): split unmatched scan folders into pseudo-app rows"
```

### Task B2: Pseudo-app rows exempt from small-file fold

**Files:**
- Modify: `kSpaceClean/Features/SmartScan/Views/ScanResultsViewModel.swift` (`annotateSubHidden`, lines 597-613)
- Test: `kSpaceClean/Tests/ScanTreeFilterTests.swift` (append `PseudoAppFilterExemptionTests`)

**Interfaces:**
- Consumes: `ScanSubCategory.isPseudoApp` + `totalSize` (from B1).
- Produces: `annotateSubHidden` keeps pseudo-app rows with content visible even when every leaf is sub-100KB; `ScanResultsViewHiddenRenderingTests` behavior unchanged.

- [ ] **Step 1: Write the failing tests**

Append to the END of `kSpaceClean/Tests/ScanTreeFilterTests.swift`:

```swift
@MainActor
final class PseudoAppFilterExemptionTests: XCTestCase {
    func testPseudoAppRowWithContentNeverFoldsUpHidden() {
        let result = ScanResult(
            url: URL(fileURLWithPath: "/tmp/folder/file.bin"),
            path: "/tmp/folder/file.bin",
            title: "file.bin",
            fileSize: 100,
            cleanType: .cache
        )
        let pseudo = ScanSubCategory(
            subCategoryID: "c1.folder.SomeApp",
            title: "SomeApp",
            totalSize: 100,
            directResults: [result],
            showAction: false,
            riskLevel: .caution,
            isRecommended: false,
            isPseudoApp: true
        )
        let cat = ScanCategory(categoryID: "c1", title: "Test", subItems: [pseudo])

        let options = ScanFilterOptions(minimumSizeBytes: 102_400)  // 100 KB
        let resultCat = try! XCTUnwrap(
            ScanResultsViewModel.annotateHidden([cat], options: options, now: Date()).first
        )
        let resultSub = try! XCTUnwrap(resultCat.subItems.first)
        XCTAssertFalse(resultSub.isHiddenByFilter,
                       "pseudo-app row with content must stay visible even when all leaves are sub-100KB")
        XCTAssertFalse(resultCat.isHiddenByFilter,
                       "a visible pseudo-app row must keep its parent category visible too")
    }

    func testRegularSubWithAllHiddenLeavesFoldsUp() {
        let result = ScanResult(
            url: URL(fileURLWithPath: "/tmp/folder/file.bin"),
            path: "/tmp/folder/file.bin",
            title: "file.bin",
            fileSize: 100,
            cleanType: .cache
        )
        let sub = ScanSubCategory(
            subCategoryID: "s1",
            title: "Regular",
            totalSize: 100,
            directResults: [result],
            showAction: false,
            isRecommended: false
        )
        let cat = ScanCategory(categoryID: "c1", title: "Test", subItems: [sub])

        let options = ScanFilterOptions(minimumSizeBytes: 102_400)
        let resultCat = try! XCTUnwrap(
            ScanResultsViewModel.annotateHidden([cat], options: options, now: Date()).first
        )
        let resultSub = try! XCTUnwrap(resultCat.subItems.first)
        XCTAssertTrue(resultSub.isHiddenByFilter,
                      "control: a regular sub with all leaves hidden folds up hidden")
        XCTAssertTrue(resultCat.isHiddenByFilter)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" /Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild -project kSpaceClean/kSpaceClean.xcodeproj -scheme kSpaceClean -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO ONLY_ACTIVE_ARCH=YES -only-testing:kSpaceCleanTests/PseudoAppFilterExemptionTests test
```
Expected: FAIL — the pseudo-app row computes `allHidden == true` and folds up.

- [ ] **Step 3: Add the exemption in `annotateSubHidden`**

In `ScanResultsViewModel.swift`, replace lines 597-599:

```swift
        let childrenHidden = actions.allSatisfy(\.isHiddenByFilter)
            && direct.allSatisfy(\.isHiddenByFilter)
        let allHidden = !(actions.isEmpty && direct.isEmpty) && childrenHidden
```

with:

```swift
        let childrenHidden = actions.allSatisfy(\.isHiddenByFilter)
            && direct.allSatisfy(\.isHiddenByFilter)
        // Task B2: a pseudo-app row with any content is exempt from the
        // small-file fold — it must stay visible even when every leaf is
        // sub-100KB (the row is the only "name" the user has for that folder).
        let pseudoExempt = sub.isPseudoApp && sub.totalSize > 0
        let allHidden = !(actions.isEmpty && direct.isEmpty) && childrenHidden && !pseudoExempt
```

In the rebuild below (lines 600-613), insert `isPseudoApp: sub.isPseudoApp,` between `isRecommended: sub.isRecommended,` and `isHiddenByFilter: allHidden`.

- [ ] **Step 4: Run the tests to verify they pass**

Same `-only-testing:kSpaceCleanTests/PseudoAppFilterExemptionTests` command. Expected: 2/2 PASS.

- [ ] **Step 5: Run the full suite**

Full test command. Expected: 282 passing (280 + 2 B2).

- [ ] **Step 6: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && git add kSpaceClean/Features/SmartScan/Views/ScanResultsViewModel.swift kSpaceClean/Tests/ScanTreeFilterTests.swift && git commit -m "feat(kSpaceClean): exempt pseudo-app rows from small-file fold"
```

### Task B3: Rule library 108 → 151 (43 user-installed apps)

**Files:**
- Modify: `kSpaceClean/Resources/bundleIDMapping.json` (`appCount` → 151, insert 43 entries)
- Modify: `kSpaceClean/Tests/AppRuleFixtures.swift` (add `task12BundleIDs` + 2 tests in `AppRuleLibraryAudit`)

**Interfaces:**
- Consumes: existing JSON v2 schema, `AppRuleLibraryAudit.mappingURL` / `root` helpers, `newBundleIDs`/`task9BundleIDs`/`task10BundleIDs` pattern.
- Produces: `task12BundleIDs` (43 entries), `testTask12NewAppsPresentWithV2Actions`, `testTask12AppsNeverCoverBareUserDataRoots`. Consumed by B4 (full suite + JSON validation).

- [ ] **Step 1: Write the failing tests**

In `AppRuleFixtures.swift` inside `AppRuleLibraryAudit`, add after the `task10BundleIDs` declaration (line 206):

```swift
    /// The 43 net-new apps mandated by the Task B3 controller resolution
    /// (user-installed apps missing from the 108-entry library; includes
    /// DingTalk's two variants).
    private let task12BundleIDs = [
        "org.115Browser.115Browser",
        "com.baidu.BaiduNetdisk-mac",
        "com.ScooterSoftware.BeyondCompare",
        "com.ccswitch.desktop",
        "org.cmake.cmake",
        "com.xk72.Charles",
        "com.tencent.codebuddycn",
        "net.sourceforge.sqlitebrowser",
        "com.fiplab.appshredder",
        "com.bot.neotix.doubao",
        "com.trendmicro.DrUnzip",
        "com.getdropbox.dropbox",
        "com.tencent.Foxmail",
        "com.cryptic-apps.hopper-web-4",
        "com.microsoft.Powerpoint",
        "com.microsoft.rdc.macos",
        "com.microsoft.Word",
        "com.MockingBot.MockingBotMAC",
        "org.outline.macos.client",
        "com.postmanlabs.mac",
        "com.initex.proxifier.macosx",
        "com.alibaba.tongyi",
        "clowwindy.ShadowsocksX",
        "com.sogou.SogouInputSwitchHelper",
        "com.torusknot.SourceTreeNotMAS",
        "org.springframework.boot.ide.branding.sts4",
        "com.surfshark.vpnclient.macos.direct",
        "com.tencent.Lemon",
        "com.tencent.meeting",
        "com.culturedcode.ThingsMac",
        "com.vmware.fusion",
        "com.vscode.weterm",
        "com.tencent.mac.weiyun",
        "org.wireshark.Wireshark",
        "com.xiaomi.xmrouter",
        "com.youdao.note.YoudaoNoteMac",
        "net.toolinbox.ihosts",
        "cn.better365.ishot",
        "com.googlecode.iterm2",
        "com.krightmenu.app",
        "com.yinxiang.Mac",
        "com.dingtalk.mac",
        "5ZSL2CJU2T.com.dingtalk.mac",
    ]
```

Add these two test methods (mirror `testTask8NewAppsPresentWithV2Actions`, lines 264-277) before the closing brace of `AppRuleLibraryAudit` (line 473):

```swift
    /// Task B3: all 43 net-new apps are present, use the v2 actions schema,
    /// and declare an explicit `appstoreBundleID: null`.
    func testTask12NewAppsPresentWithV2Actions() throws {
        let apps = try XCTUnwrap(root["apps"] as? [String: [String: Any]])
        for bundleID in task12BundleIDs {
            let app = try XCTUnwrap(apps[bundleID],
                                    "Task B3 app \(bundleID) missing from bundleIDMapping.json")
            XCTAssertTrue(app["appstoreBundleID"] is NSNull,
                          "\(bundleID) must declare appstoreBundleID: null")
            let actions = try XCTUnwrap(app["actions"] as? [[String: Any]],
                                        "\(bundleID) must use the v2 actions schema")
            XCTAssertFalse(actions.isEmpty, "\(bundleID) has empty actions[]")
        }
    }

    /// Task B3 SAFETY CONSTRAINT: the 43 net-new apps must never declare a
    /// cleanable action at a bare user-data root — either the
    /// `Application Support/<Leaf>/` root (chat/model databases) or the
    /// `Containers/<Bundle>/Data` container home. Actions must be scoped to
    /// cache/log subdirs. Banned shapes are matched by path shape so new
    /// entries cannot sneak a bare root back in.
    func testTask12AppsNeverCoverBareUserDataRoots() throws {
        let apps = try XCTUnwrap(root["apps"] as? [String: [String: Any]])
        for bundleID in task12BundleIDs {
            let app = try XCTUnwrap(apps[bundleID],
                                    "\(bundleID) missing from bundleIDMapping.json")
            let actions = try XCTUnwrap(app["actions"] as? [[String: Any]],
                                        "\(bundleID) must use the v2 actions schema")
            for action in actions {
                let paths = try XCTUnwrap(action["paths"] as? [String])
                for path in paths {
                    let comps = path.split(separator: "/")
                    for i in 0..<comps.count {
                        // Banned shape 1: "…/Application Support/<Leaf>/" with
                        // nothing after it — the leaf root holds user data.
                        if comps[i] == "Application Support", i == comps.count - 2 {
                            XCTFail("\(bundleID) action \(action["name"] ?? "?") declares "
                                + "bare App Support root \(path) — leaf root is user data; "
                                + "cache/log subdirs only")
                        }
                        // Banned shape 2: "…/Containers/<Bundle>/Data" — the
                        // container home holds the sandboxed app data.
                        if comps[i] == "Containers", i == comps.count - 3,
                           comps[i + 2] == "Data" {
                            XCTFail("\(bundleID) action \(action["name"] ?? "?") declares "
                                + "bare container home \(path) — container data is user data; "
                                + "scope to <container>/Data/Library/Caches/…")
                        }
                    }
                }
            }
        }
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" /Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild -project kSpaceClean/kSpaceClean.xcodeproj -scheme kSpaceClean -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO ONLY_ACTIVE_ARCH=YES -only-testing:kSpaceCleanTests/AppRuleLibraryAudit/testTask12NewAppsPresentWithV2Actions -only-testing:kSpaceCleanTests/AppRuleLibraryAudit/testTask12AppsNeverCoverBareUserDataRoots test
```
Expected: FAIL — every `task12BundleIDs` entry is missing from the JSON.

- [ ] **Step 3: Verify real cache paths for the 43 installed apps**

All 43 apps are installed on this machine. For EACH bundle ID, resolve its real cache/log dirs. Run this per-app protocol (verbatim):

```bash
# 1. Bundle-ID-scoped cache/log dirs
for d in \
  "$HOME/Library/Caches/<bundleID>" \
  "$HOME/Library/Logs/<bundleID>" \
  "$HOME/Library/Containers/<bundleID>/Data/Library/Caches"; do
  [ -d "$d" ] && echo "EXISTS $d"
done
# 2. Apps that do NOT use their bundle ID as the cache folder name:
ls "$HOME/Library/Caches" | grep -i '<keyword>'          # e.g. "dropbox", "iterm", "postman"
ls "$HOME/Library/Application Support" | grep -i '<keyword>'   # e.g. "Beyond Compare", "SourceTree"
# 3. For containerized apps (e.g. Postman, DingTalk):
ls "$HOME/Library/Containers" | grep -i '<keyword>'
```

Path-selection rules (SAFETY, binding):
- Declare `~/Library/Caches/<dir>/` paths (type `"appcache"`) — highest confidence.
- Declare `~/Library/Logs/<dir>/` paths (type `"file"`) when they exist.
- For containerized apps, declare `~/Library/Containers/<Bundle>/Data/Library/Caches/...` **subdirs only** — NEVER the bare `<Bundle>/Data` home.
- For `Application Support` dirs, declare a **scoped cache/log subdir only** (e.g. `~/Library/Application Support/SourceTree/cache/`), NEVER the bare `Application Support/<Leaf>/` root.
- If an app has no cleanable cache/log dir on this machine, give it ONE minimal appcache action pointing at its bundle-ID Caches dir ONLY if that dir exists; otherwise give it an actions entry with a single `"file"` action at its Logs dir. Every entry must have ≥1 action (the presence test requires non-empty).
- Display names (`name`/`nameCN`) come from `/Applications`: `mdls -name kCFBundleDisplayName -name kCFBundleName "/Applications/<App>.app"`; `nameCN` is the Chinese equivalent (match the app's zh-Hans localization, or transliterate for the known CN apps).
- `vendor` = company name (read from Info.plist `kMDItemVersion`-adjacent or the app's developer). `type` = app category keyword (e.g. `network`, `office`, `devtools`, `chat`, `utility`, `media`).

- [ ] **Step 4: Insert the 43 entries into `bundleIDMapping.json`**

Update the header `"appCount": 108` → `"appCount": 151`. Insert one entry per app into `"apps"`. Entry template (match the existing style exactly — note `appstoreBundleID` is JSON `null`, NOT the string `"null"`):

```json
    "com.xk72.Charles": {
      "bundleID": "com.xk72.Charles",
      "appstoreBundleID": null,
      "nameCN": "Charles 缓存",
      "name": "Charles Caches",
      "actions": [
        {
          "nameCN": "Charles 缓存",
          "name": "Charles Cache",
          "type": "appcache",
          "paths": ["~/Library/Caches/com.xk72.Charles/"]
        }
      ],
      "vendor": "XK72 Ltd",
      "type": "network",
      "riskLevel": "caution",
      "confidence": "medium"
    }
```

Remember: dict key MUST equal `bundleID`; every action path MUST be `~/`-rooted or absolute; the path selection rules in Step 3 are binding.

- [ ] **Step 5: Run the B3 tests + JSON validation**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && python3 -c "import json; json.load(open('kSpaceClean/Resources/bundleIDMapping.json'))"
```
Expected: no output, exit 0.

Run the `-only-testing:kSpaceCleanTests/AppRuleLibraryAudit` command from Step 2. Expected: 2/2 PASS. Also confirm `testMappingHeaderAndStructuralInvariants` and `testTask8NewAppsPresentWithV2Actions` still pass (run the whole `AppRuleLibraryAudit` class).

- [ ] **Step 6: Run the full suite**

Full test command. Expected: 284 passing (282 + 2 B3).

- [ ] **Step 7: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && git add kSpaceClean/Resources/bundleIDMapping.json kSpaceClean/Tests/AppRuleFixtures.swift && git commit -m "feat(kSpaceClean): grow rule library 108→151 with user-installed apps"
```

### Task B4: Full suite + build + visual smoke + commit

**Files:** none (verification only).

**Interfaces:** Consumes all A1/A2/B1/B2/B3 changes.

- [ ] **Step 1: Run the full test suite**

Run the full test command (Global Constraints). Expected: **284 passing, 0 failing.**

- [ ] **Step 2: Validate the JSON**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && python3 -c "import json; json.load(open('kSpaceClean/Resources/bundleIDMapping.json'))"
```
Expected: no output, exit 0.

- [ ] **Step 3: Build the app**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" /Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild -project kSpaceClean/kSpaceClean.xcodeproj -scheme kSpaceClean -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO ONLY_ACTIVE_ARCH=YES build
```
Expected: BUILD SUCCEEDED, zero warnings.

- [ ] **Step 4: Visual smoke test**

Launch the built `kSpaceClean.app` (in `kSpaceClean/build/Debug/` or the `-derivedDataPath` build products). Run a scan. Verify:
- Progress screen shows a live ring moving continuously (not frozen near 0), a moving current-file path, a real 速度 (files/秒) number, and a 预计剩余 (ETA) column that counts down.
- Scan results show real app rows under each category — e.g. under 应用缓存 you see actual app names (Claude Code / Cursor / Postman / Dropbox / etc.), NOT a single duplicated "应用缓存 → 应用缓存".
- Unmatched top-level folders appear as pseudo-app rows titled with the folder name; they are UNCHECKED by default and do not disappear when the "显示过滤掉的项" toggle is off.
- The "其他未识别" sentinel row exists (if any files sit directly in a category root).
- Toggling "显示过滤掉的项" reveals sub-100KB files as before; pseudo-app rows with content stay visible.

- [ ] **Step 5: Commit any leftovers**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1 && git status
```
If clean, no commit. If anything is left over, commit with `chore: post-scan-ux-v2 verification`.

- [ ] **Step 6: Record the 500+ release-gate TODO**

Append one line to `.superpowers/sdd/progress.md`:

```
TODO (release gate, iterative): rule library 500+ target — 151 now; expand via AI-assisted + reference-product patterns (CMM/Buho/Lemon logic, no rule copy). See memory project_kraftly_rule_target.
```

---

## Execution Handoff

This plan is complete and saved to `docs/superpowers/plans/2026-08-02-kspaceclean-scan-ux-v2.md`.

**Recommended execution: subagent-driven-development** — dispatch a fresh implementer subagent per task, run a spec-compliance + code-quality review between tasks, and a broad final review at the end. Task B3 (43-app rule research) is best delegated to an implementer with isolated context, briefed with the bundle-ID table above.
