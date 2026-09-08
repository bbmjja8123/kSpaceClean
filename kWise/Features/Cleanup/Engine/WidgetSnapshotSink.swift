// kWise/Features/Cleanup/Engine/WidgetSnapshotSink.swift
//
// App-side snapshot feeder (v2.0 Phase 6). Every finished cleanup updates
// the widget feed through the same event stream the quota ledger uses, and
// the disk numbers refresh opportunistically — no background agent.
import Foundation
import WidgetKit

public struct WidgetSnapshotSink: CleanupEventSink {
    public let store: WidgetSnapshotStore

    public init(store: WidgetSnapshotStore = WidgetSnapshotStore()) {
        self.store = store
    }

    public func cleanupDidFinish(_ event: CleanupEvent) async {
        guard event.freedBytes > 0 else { return }
        store.update { snapshot in
            snapshot.lastCleanup = WidgetSnapshot.LastCleanup(
                freedBytes: event.freedBytes,
                date: event.date
            )
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Refresh the disk numbers. Called on app launch and after scans.
    public static func refreshDiskInfo(store: WidgetSnapshotStore = WidgetSnapshotStore()) {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? homeURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        ) else { return }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let available = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        store.update { snapshot in
            snapshot.disk = WidgetSnapshot.DiskInfo(
                usedBytes: max(0, total - available),
                totalBytes: total
            )
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
