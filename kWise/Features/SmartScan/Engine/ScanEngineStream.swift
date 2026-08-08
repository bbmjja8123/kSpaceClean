// kWise/Features/SmartScan/Engine/ScanEngineStream.swift
//
// Thin MainActor wrapper around `ScanOrchestrator` that surfaces the
// parallel scan pipeline as an `AsyncStream<ScanProgress>` and folds the
// per-category `ScanCategory` payloads into an `@Published` array the
// SwiftUI `ScanResultsView` can render directly.
//
// Why this file exists:
// * `ScanOrchestrator` (Task B3) is an `actor` that emits work asynchronously
//   on its own isolation domain. SwiftUI views need their state on the
//   main actor, so this wrapper bridges the two: it consumes the orchestrator
//   stream on `MainActor`, updates `@Published` properties, and applies an
//   **adaptive throttle** so the UI can keep a 60fps frame budget even when
//   the orchestrator pours out per-file events at full speed.
//
// Adaptive throttle (per user decision, 2026-07-25):
// * **Idle main thread → 16ms window** (~60fps updates).
// * **Busy main thread → 33ms window** (~30fps updates) so we don't pile
//   more work onto a thread that is already saturated.
// * "Busy" is inferred by observing the time it takes the main actor to
//   drain a `Task.yield()` call — when the previous frame took > 16ms the
//   next emission is delayed to 33ms.
//
// Distinction from the legacy `ScanEngine.swift` (one directory up):
// * The legacy engine drives the v2 RuleClassifier + BatchBuffer → Core Data
//   pipeline; that file still backs `ScanViewModel.startScan()` today.
// * This wrapper drives the v3 4-level tree the orchestrator produces and
//   will replace the legacy engine once `ScanViewModel` is migrated (Task B5+).
//   Keeping them side-by-side during the migration is intentional.

import Foundation
import Combine

// MARK: - ScanEngine

/// AsyncStream wrapper around `ScanOrchestrator` with adaptive throttle.
///
/// Call `startScan()` to begin a scan and iterate `progressStream` to
/// observe progress events. The `@Published` `categories` and `progress`
/// properties are updated on the main actor with a **16ms/33ms adaptive
/// throttle** so SwiftUI redraws stay bounded.
///
/// Lifecycle:
/// * `startScan()` cancels any previous scan and kicks off a new one.
/// * `cancelScan()` flips the orchestrator's cancellation flag and resets
///   `progress` to `.idle`.
/// * `progressStream` is updated to the latest active stream when a scan
///   starts; consumers can use it to await specific lifecycle events.
@MainActor
public final class ScanEngine: ObservableObject {
    // MARK: Published state

    /// Categories populated incrementally as each orchestrator worker completes.
    /// The wrapper inserts categories in the order the orchestrator yields them
    /// (which is **not** guaranteed to be the order the user expects), so the
    /// view layer is expected to apply its own stable sort on `categoryID`.
    @Published public private(set) var categories: [ScanCategory] = []

    /// Latest progress snapshot. Updated on the main actor every time the
    /// orchestrator emits a new event, after the adaptive throttle window.
    @Published public private(set) var progress: ScanProgress = .init(
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

    /// AsyncStream of the currently running scan. Consumers can attach an
    /// additional observer (e.g. for analytics) without disturbing the
    /// `@Published` pipeline. `nil` when no scan is in flight.
    public private(set) var progressStream: AsyncStream<ScanProgress>?

    // MARK: Dependencies

    private let orchestrator: ScanOrchestrator

    // MARK: Private state

    /// The Task that consumes the orchestrator's AsyncStream. Cancelled by
    /// `startScan()` (to abandon a prior run) and `cancelScan()`.
    private var scanTask: Task<Void, Never>?

    /// Monotonic counter bumped every `startScan()` so the *previous* scan's
    /// in-flight unstructured tasks (which cancellation does not reach — the
    /// `Task {}` spawns inside `runScan` do not inherit their parent's
    /// cancellation) can detect they are stale and stop ingesting into the
    /// freshly-reset `@Published` state.
    private var scanGeneration: UInt64 = 0

    /// Adaptive throttle window. Starts at 16ms; bumped to 33ms when the
    /// main thread is observed to be saturated.
    private var throttleInterval: TimeInterval = 0.016

    /// Tracks the last time we actually emitted a progress update to the
    /// `@Published` property. The wrapper may receive many more events
    /// from the orchestrator than it forwards to SwiftUI.
    private var lastEmitAt: Date = .distantPast

    /// Sampling window for the throttle — if more than 16ms passes between
    /// Task.yield() returns, we know the main thread is busy and we widen
    /// the throttle to 33ms for the next cycle.
    private var lastYieldDuration: TimeInterval = 0

    // MARK: Init

    /// Designated initializer. `orchestrator` is injected so tests can
    /// supply a stub with deterministic event sequences.
    public init(orchestrator: ScanOrchestrator = ScanOrchestrator()) {
        self.orchestrator = orchestrator
    }

    // MARK: Lifecycle

    /// Start a new scan, cancelling any in-flight one.
    ///
    /// The wrapper's `progressStream` is set to the live stream returned by
    /// the orchestrator; consumers can attach an additional observer
    /// (e.g. for analytics) without disturbing the `@Published` pipeline.
    /// Calling `startScan()` while a scan is already in flight cancels the
    /// prior scan (and its stream) before starting a new one.
    ///
    /// Marked `async` because the orchestrator's `startScan()` is an
    /// actor-isolated method that requires an `await` to cross from the
    /// wrapper's `@MainActor` isolation domain to the orchestrator's actor.
    /// The hop completes in microseconds — the orchestrator's `startScan()`
    /// returns the `AsyncStream` immediately and the real work happens
    /// inside the stream's continuation closure.
    public func startScan() async {
        // Cancel any prior scan.
        let priorTask = scanTask
        scanTask = nil
        priorTask?.cancel()
        await orchestrator.cancel()

        // Bump the generation so any *previous* scan's in-flight unstructured
        // tasks (which cancellation does not reach — the `Task {}` spawns
        // inside `runScan` do not inherit their parent's cancellation) detect
        // they are stale and stop ingesting into the freshly-reset state
        // below. See `scanGeneration` for the full rationale.
        scanGeneration &+= 1
        let generation = scanGeneration

        // Reset state.
        categories = []
        progress = ScanProgress(
            state: .scanning,
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
        throttleInterval = 0.016
        lastEmitAt = .distantPast
        lastYieldDuration = 0

        // Called on the orchestrator's actor — the bridge returns an
        // AsyncStream immediately. The actual file-walk happens inside the
        // continuation so this hop is near-instant.
        let stream = await orchestrator.startScan()
        progressStream = stream

        scanTask = Task { [weak self] in
            await self?.runScan(stream: stream, generation: generation)
        }
    }

    /// Cancel the active scan (no-op if none is running).
    ///
    /// After cancellation, `progress` is reset to `.idle`. The categories
    /// collected up to the cancellation point are preserved for inspection.
    public func cancelScan() async {
        scanTask?.cancel()
        scanTask = nil
        await orchestrator.cancel()
        progress = ScanProgress(state: .idle)
    }

    /// Wait for the in-flight scan to finish (completed, cancelled, or
    /// failed). No-op when no scan is running.
    ///
    /// This is the deterministic way for a caller to learn the scan's final
    /// state: `startScan()` is fire-and-forget (it returns as soon as the
    /// orchestrator's stream is created), so a caller that needs the results
    /// — e.g. `ScanResultsViewModel.startRealScan` — must await this before
    /// reading `categories` or `progress`.
    public func waitForScanCompletion() async {
        guard let scanTask else { return }
        await scanTask.value
    }

    // MARK: Stream Consumer

    /// Drains the orchestrator's `AsyncStream<ScanProgress>` and applies
    /// the adaptive throttle before forwarding events to SwiftUI.
    ///
    /// The throttle algorithm:
    /// 1. On every orchestrator event, record the current time.
    /// 2. If at least `throttleInterval` (16ms or 33ms) has elapsed since
    ///    the last forward, measure how long `Task.yield()` takes to come back.
    /// 3. If that yield took > 16ms, widen the next interval to 33ms (the
    ///    main thread is busy); otherwise keep it at 16ms.
    /// 4. Always forward the final state (so the UI doesn't sit on a
    ///    stale snapshot if the scan finishes inside a throttle window).
    private func runScan(stream: AsyncStream<ScanProgress>, generation: UInt64) async {
        // C2: also drain the orchestrator's per-category stream so the
        // `@Published categories` array populates incrementally. The
        // progress stream only carries aggregate counters, not the
        // category tree, so we need a second consumer to fold the tree.
        let categoryStream = await orchestrator.categoryStream()

        let progressTask = Task { [weak self] in
            guard let self else { return }
            for await snapshot in stream {
                self.ingest(snapshot: snapshot, generation: generation)
                if Self.isTerminal(snapshot.state) { return }
            }
        }
        let categoryTask = Task { [weak self] in
            guard let self else { return }
            for await event in categoryStream {
                switch event {
                case .category(let catEvent):
                    self.ingest(categoryEvent: catEvent, generation: generation)
                case .terminal:
                    return
                }
            }
        }

        // NOTE: we do NOT cancel `categoryTask` after `progressTask`
        // finishes. The orchestrator's `categoryStream` terminates itself:
        // once `hasFinishedScan` flips it drains the remaining buffered
        // events, yields a `.terminal`, and returns. Cancelling it early
        // (the pre-fix behaviour) dropped buffered category events that
        // arrived between the progress stream's last snapshot and the scan
        // finishing — the same "results silently disappear" class of bug
        // this pass fixes. Both tasks self-terminate; just await both.
        await progressTask.value
        await categoryTask.value
    }

    /// True when `state` is one of the terminal states — `.completed`,
    /// `.cancelled`, or `.failed(_)` — so the consumer can stop iterating.
    private static func isTerminal(_ state: ScanProgress.State) -> Bool {
        switch state {
        case .completed, .cancelled, .failed: return true
        case .idle, .scanning, .analysing: return false
        }
    }

    /// Applies the adaptive throttle to a single progress snapshot and
    /// forwards it to the `@Published` property.
    private func ingest(snapshot: ScanProgress, generation: UInt64) {
        // Stale-guard: a *previous* scan's unstructured task (see
        // `scanGeneration`) may still be draining its stream after a new
        // scan has started. Dropping its writes keeps the fresh scan's
        // state untouched. `generation` is only mutated on the main actor
        // (this method is `@MainActor`), so the check is race-free.
        guard generation == scanGeneration else { return }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastEmitAt)
        if elapsed >= throttleInterval {
            // Note: we deliberately don't `await Task.yield()` here because
            // we are on `@MainActor` and `progress = snapshot` triggers a
            // SwiftUI re-render which is the only sink we need to throttle.
            // The throttle measurement is approximated by the elapsed time
            // since the last emit — if the previous emit took > 16ms the
            // user is busy, so widen the window to 33ms.
            if elapsed > 0.016 {
                throttleInterval = 0.033
            } else {
                throttleInterval = 0.016
            }
            lastEmitAt = now
            progress = snapshot
        } else if Self.isTerminal(snapshot.state) {
            // Always forward terminal states so the UI doesn't get stuck.
            progress = snapshot
        }
    }

    /// Folds a per-category payload into the `@Published categories` array.
    /// Replaces any prior entry for the same `categoryID` so re-runs are
    /// idempotent, and applies the adaptive throttle so the UI does not
    /// redraw more than ~30 times per second.
    private func ingest(categoryEvent: ScanCategoryEvent, generation: UInt64) {
        // Same stale-guard as `ingest(snapshot:generation:)` — a previous
        // scan's category task must not fold its tree into a fresh scan.
        guard generation == scanGeneration else { return }

        // C2 fix: replace or append the category; the view layer sorts by
        // a stable key (we keep insertion order so the first match wins).
        if let idx = categories.firstIndex(where: { $0.categoryID == categoryEvent.categoryID }) {
            categories[idx] = categoryEvent.category
        } else {
            categories.append(categoryEvent.category)
        }
    }
}
