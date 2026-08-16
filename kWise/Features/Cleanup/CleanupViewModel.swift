@preconcurrency import CoreData
import Foundation
import SwiftUI

@MainActor
public final class CleanupViewModel: ObservableObject {
    @Published public var isCleaning = false
    @Published public var lastResult: TrashResult?
    @Published public var cleanupHistory: [CleanupHistoryItem] = []
    /// Pending cleanup list — set externally (e.g. by the Smart Care
    /// orchestrator's `.confirm()` or the CleanupContentView confirm dialog)
    /// before calling ``cleanupNow()``. Empty list = no-op.
    @Published public var urlsToCleanup: [URL] = []
    private let mover = TrashMover()
    private let history = CleanupHistory()
    /// Structured-API engine — used by ``cleanupNow()`` and the
    /// `CleanupContentView` confirmation flow. Defaults to a fresh instance
    /// driven by the shared `PersistenceController`.
    private let engine: CleanupEngine

    public init(engine: CleanupEngine = CleanupEngine()) {
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
    public func cleanupNow() async {
        let urls = urlsToCleanup
        guard !urls.isEmpty else { return }
        isCleaning = true
        defer {
            isCleaning = false
            Task { await self.refreshHistory() }
        }
        let targets = urls.map { url -> CleanupTarget in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? 0
            return CleanupTarget(url: url, size: size, risk: .recommended)
        }
        do {
            let outcome = try await engine.cleanup(targets: targets)
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
        } catch {
            // Phase B Task 5: best-effort; UI shows the error via `lastResult`.
            self.lastResult = nil
        }
    }

    public func refreshHistory() async {
        cleanupHistory = history.fetchRecent()
    }
}

// MARK: - Engine termination helper

extension CleanupEngine {
    /// Send `terminate()` to every running app whose bundleID matches a
    /// target's `bundleID`. Falls back to `forceTerminate()` for unresponsive
    /// apps. Best-effort — silently skips apps that don't own any target.
    fileprivate func terminateOwningApps(for targets: [CleanupTarget]) {
        let targetBundleIDs = Set(targets.compactMap(\.bundleID))
        guard !targetBundleIDs.isEmpty else { return }
        for app in NSWorkspace.shared.runningApplications
            where app.bundleIdentifier.map(targetBundleIDs.contains) == true {
            app.terminate()
        }
        // Force-terminate anything still hanging around after a beat.
        let liveAppBundleIDs = Set(
            NSWorkspace.shared.runningApplications
                .compactMap(\.bundleIdentifier)
        )
        for bundleID in targetBundleIDs.intersection(liveAppBundleIDs) {
            if let app = NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == bundleID }) {
                app.forceTerminate()
            }
        }
    }
}