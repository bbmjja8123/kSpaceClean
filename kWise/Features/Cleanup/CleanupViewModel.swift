@preconcurrency import CoreData
import Foundation
import SwiftUI

@MainActor
public final class CleanupViewModel: ObservableObject {
    @Published public var isCleaning = false
    @Published public var lastResult: TrashResult?
    /// Raw engine outcome of the last structured run — the scan surface's
    /// confirm sheet shows the truthful freed bytes from here (the legacy
    /// `TrashResult` records `fileSize: 0`, so it cannot).
    @Published public private(set) var lastOutcome: CleanupOutcome?
    @Published public var cleanupHistory: [CleanupHistoryItem] = []
    /// Pending cleanup list — set externally (e.g. by the Smart Care
    /// orchestrator's `.confirm()` or the CleanupContentView confirm dialog)
    /// before calling ``cleanupNow()``. Empty list = no-op.
    @Published public var urlsToCleanup: [URL] = []
    private let mover = TrashMover()
    private let history = CleanupHistory()
    /// Structured-API engine — used by ``cleanupNow()`` and the
    /// `CleanupContentView` confirmation flow. Defaults to a fresh instance
    /// driven by the shared `PersistenceController`; the app root re-points
    /// it at the graph engine (quota + sinks) in `.onAppear`.
    private(set) var engine: CleanupEngine

    /// Invoked when a run leaves targets behind because the free quota was
    /// exhausted — the root presents the paywall (never the view itself).
    public var onQuotaExhausted: (() -> Void)?

    public init(engine: CleanupEngine? = nil) {
        // Resolve on the main actor so `CleanupEngine.standard()` is legal.
        self.engine = engine ?? CleanupEngine.standard()
    }

    /// Re-point at the shared graph engine (v2.0 Phase 1 DI unification).
    public func useEngine(_ engine: CleanupEngine) {
        self.engine = engine
    }

    public func moveToTrash(urls: [URL]) async {
        isCleaning = true
        let result = await mover.moveToTrash(urls: urls)
        lastResult = result

        // Record each successful move using the actual trash path and file size
        // from the snapshot. The new engine (Task C2) owns history writes for the
        // structured API; this view-model still supports the lightweight
        // TrashMover-driven flow used by some UI surfaces.
        let persistence = PersistenceController.shared
        let context = persistence.newBackgroundContext()
        await context.perform { [persistence] in
            for snapshot in result.snapshots {
                let target = CleanupTarget(
                    url: URL(fileURLWithPath: snapshot.originalPath),
                    size: snapshot.fileSize,
                    risk: .recommended
                )
                persistence.insertHistory(targets: [target], in: context)
            }
            persistence.save(context: context)
        }

        isCleaning = false
        await refreshHistory()
    }

    /// Structured cleanup path — wraps `CleanupEngine.cleanup(targets:)` for
    /// the v1.5 confirmation dialog. Maps `urlsToCleanup` (raw URLs) onto
    /// `CleanupTarget`s, calls into the engine, and refreshes history on
    /// return. Errors are surfaced via `lastResult` for the UI to read.
    ///
    /// - Parameter sizes: scanned size per URL (from the selection), so the
    ///   outcome reports truthful freed bytes without a per-URL syscall
    ///   storm. `nil` = fall back to a per-URL stat.
    public func cleanupNow(sizes: [URL: Int64]? = nil) async {
        let urls = urlsToCleanup
        guard !urls.isEmpty else { return }
        isCleaning = true
        defer {
            isCleaning = false
            Task { await self.refreshHistory() }
        }
        let targets = urls.map { url -> CleanupTarget in
            let size = sizes?[url]
                ?? (try? url.resourceValues(forKeys: [.fileSizeKey])).flatMap { $0.fileSize.map(Int64.init) }
                ?? 0
            return CleanupTarget(url: url, size: size, risk: .recommended)
        }
        do {
            let outcome = try await engine.cleanup(targets: targets)
            self.lastOutcome = outcome
            // Best-effort conversion into the legacy TrashResult shape so the
            // history list view keeps rendering through the existing
            // `lastResult` accessor.
            let succeededSnapshots = outcome.succeeded.map { url in
                TrashSnapshot(
                    originalPath: url.path,
                    trashPath: url.path,
                    fileSize: 0,
                    modifiedAt: Date()
                )
            }
            let failed: [(URL, TrashMover.MoveError)] = outcome.failed.map {
                ($0.url, .trashFailed($0.url, NSError(domain: "CleanupEngine", code: 0)))
            }
            self.lastResult = TrashResult(snapshots: succeededSnapshots, failed: failed)
            self.urlsToCleanup = []
            if outcome.quotaExhausted {
                onQuotaExhausted?()
            }
        } catch {
            // Phase B Task 5: best-effort; UI shows the error via `lastResult`.
            self.lastResult = nil
        }
    }

    public func refreshHistory() async {
        cleanupHistory = history.fetchRecent()
    }
}
