// kWise/Persistence/CoreDataModels/CleanupHistoryItem.swift
import CoreData
import Foundation

/// One cleaned path, recorded so the user can review (and eventually restore) it.
///
/// Rows are written *before* the trash move in `CleanupEngine` (Task C2) so that a
/// crash mid-cleanup still leaves an audit trail. Rows older than 30 days are removed
/// lazily by `PersistenceController.purgeExpiredHistory(olderThan:)` — there is no
/// background timer, the purge runs when the app next touches the history.
///
/// Codegen is Manual/None: the entity is declared in
/// `Resources/kWise.xcdatamodeld` and this file is the hand-written companion.
@objc(CleanupHistoryItem)
public class CleanupHistoryItem: NSManagedObject {
}

extension CleanupHistoryItem {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CleanupHistoryItem> {
        NSFetchRequest<CleanupHistoryItem>(entityName: "CleanupHistoryItem")
    }

    /// Stable identity for diffing in SwiftUI lists.
    @NSManaged public var id: UUID?
    /// Absolute path of the item at the time it was cleaned.
    @NSManaged public var path: String?
    /// Size in bytes captured before the move to trash.
    @NSManaged public var size: Int64
    /// When the cleanup happened — also the key for the 30-day expiry predicate.
    @NSManaged public var cleanedAt: Date?
    /// Owning app's bundle identifier when known (e.g. cache belonging to Xcode).
    @NSManaged public var bundleID: String?
    /// Scan category the item came from, used to group history rows by module.
    @NSManaged public var categoryID: String?
    /// `RiskLevel.persistenceKey` — stored as a string so the model survives
    /// re-ordering of the enum's raw `Int` values.
    @NSManaged public var riskLevel: String?

    // v2.0 Phase 7 — timeline grouping + per-run rollback (lightweight
    // migration: optional attributes, no versioned model needed).

    /// One GUID per `cleanup(targets:)` run — groups rows into timeline events.
    @NSManaged public var runID: UUID?
    /// `"cleanup" | "shred" | "startupItem" | nil` (nil = legacy v1 row).
    @NSManaged public var actionKind: String?
    /// When the item was restored from the Trash; nil until restored.
    @NSManaged public var restoredAt: Date?
}

extension CleanupHistoryItem {
    /// Well-known action kinds.
    public enum ActionKind {
        public static let cleanup = "cleanup"
        public static let shred = "shred"
        public static let startupItem = "startupItem"
    }

    /// Friendly kind label for the timeline; legacy rows read as cleanup.
    public var kindLabel: String {
        switch actionKind {
        case ActionKind.shred: return "粉碎"
        case ActionKind.startupItem: return "启动项"
        default: return "清理"
        }
    }

    /// Whether a restore already happened for this row.
    public var isRestored: Bool { restoredAt != nil }
}

extension CleanupHistoryItem {
    /// Typed accessor for `riskLevel`, falling back to `.recommended` for rows written
    /// by an older build or with an unrecognised string.
    public var risk: RiskLevel {
        get { RiskLevel(persistenceKey: riskLevel) ?? .recommended }
        set { riskLevel = newValue.persistenceKey }
    }

    /// Whether this row has passed the 30-day retention window and is eligible for purge.
    public func isExpired(asOf now: Date = Date(),
                          retentionDays: Int = CleanupHistoryRetention.days) -> Bool {
        guard let cleanedAt else { return true }
        return cleanedAt < CleanupHistoryRetention.cutoff(from: now, days: retentionDays)
    }
}
