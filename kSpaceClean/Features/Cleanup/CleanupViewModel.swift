import Foundation
import SwiftUI

@MainActor
public final class CleanupViewModel: ObservableObject {
    @Published public var isCleaning = false
    @Published public var lastResult: TrashResult?
    @Published public var cleanupHistory: [CleanupRecord] = []
    private let mover = TrashMover()
    private let history = CleanupHistory()

    public init() {}

    public func moveToTrash(urls: [URL]) async {
        isCleaning = true
        let result = await mover.moveToTrash(urls: urls)
        lastResult = result

        // Record each successful move using the actual trash path and file size from the snapshot
        for snapshot in result.snapshots {
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
