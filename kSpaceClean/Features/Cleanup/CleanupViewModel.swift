import Foundation
import SwiftUI

@MainActor
@Observable
public final class CleanupViewModel {
    public var isCleaning = false
    public var lastResult: TrashResult?
    public var cleanupHistory: [CleanupRecord] = []
    private let mover = TrashMover()
    private let history = CleanupHistory()

    public init() {}

    public func moveToTrash(urls: [URL]) async {
        isCleaning = true
        let result = await mover.moveToTrash(urls: urls)
        lastResult = result

        // Record each successful move in history
        for url in result.succeeded {
            let snapshot = TrashSnapshot(
                originalPath: url.path,
                trashPath: "",
                fileSize: 0,
                modifiedAt: Date()
            )
            history.recordCleanup(snapshot: snapshot)
        }

        isCleaning = false
        await refreshHistory()
    }

    public func restore(record: CleanupRecord) async -> Bool {
        let success = await history.restore(record: record)
        if success { await refreshHistory() }
        return success
    }

    public func refreshHistory() async {
        cleanupHistory = history.fetchRecent()
    }
}
