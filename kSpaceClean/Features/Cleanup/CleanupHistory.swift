// kSpaceClean/Features/Cleanup/CleanupHistory.swift
//
// Task C2 — migrated `CleanupHistory` to read the new `CleanupHistoryItem` table.
//
// Previously this file exposed a `@MainActor CleanupHistory` that wrote and read
// the legacy `CleanupRecord` entity. C1 introduced `CleanupHistoryItem`; this
// file now exposes a read-only `CleanupHistoryReader` that surfaces those rows
// to the History tab and to the cleanup view-model. Writes happen inside the
// engine (Task C2) via `PersistenceController.insertHistory`.
import CoreData
import Foundation

/// Read-only view over the `CleanupHistoryItem` table for the History tab.
@MainActor
public final class CleanupHistory {
    private let persistence: PersistenceController

    public init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    /// Fetch recent history rows newest-first.
    /// - Parameter limit: maximum rows to return; `0` means unlimited.
    public func fetchRecent(limit: Int = 50) -> [CleanupHistoryItem] {
        persistence.fetchHistory(limit: limit)
    }

    /// Sum of `size` across every history row — the total bytes the user has
    /// cleaned since the app was installed (or since the 30-day window).
    public func totalBytesFreed() -> Int64 {
        fetchRecent(limit: 0).reduce(0) { $0 + $1.size }
    }
}