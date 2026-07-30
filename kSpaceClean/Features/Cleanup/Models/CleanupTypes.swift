// kSpaceClean/Features/Cleanup/Models/CleanupTypes.swift
import Foundation

// MARK: - History retention

/// Retention policy for `CleanupHistoryItem` rows.
///
/// v1.0 keeps 30 days of history (spec §2.7 "30 天清理历史可回滚"). Expiry is enforced
/// *lazily* — `PersistenceController.purgeExpiredHistory` runs when the app opens the
/// history surface or finishes a cleanup, so there is no background timer burning energy.
public enum CleanupHistoryRetention {
    /// Number of days a cleanup record is kept before it becomes purgeable.
    public static let days = 30

    /// Timestamp before which records are considered expired.
    public static func cutoff(from now: Date = Date(), days: Int = days) -> Date {
        now.addingTimeInterval(-Double(days) * 86_400)
    }
}

// MARK: - RiskLevel persistence bridging

extension RiskLevel {
    /// Stable string key used in Core Data.
    ///
    /// The enum's `Int` raw value is deliberately *not* persisted: reordering the cases
    /// would silently re-interpret existing rows. Strings keep old data readable.
    public var persistenceKey: String {
        switch self {
        case .recommended: return "recommended"
        case .optional: return "optional"
        case .caution: return "caution"
        case .dangerous: return "dangerous"
        }
    }

    /// Inverse of `persistenceKey`. Returns `nil` for unknown / missing values so callers
    /// can decide their own fallback.
    public init?(persistenceKey: String?) {
        switch persistenceKey {
        case "recommended": self = .recommended
        case "optional": self = .optional
        case "caution": self = .caution
        case "dangerous": self = .dangerous
        default: return nil
        }
    }
}

// MARK: - Cleanup request

/// One path queued for cleanup, carrying the metadata the history row needs.
///
/// The engine (Task C2) consumes `CleanupTarget` rather than bare `URL`s so risk level
/// and provenance survive into the history table without a second lookup.
public struct CleanupTarget: Sendable, Identifiable, Hashable {
    public let id: UUID
    /// File or directory to move to the trash.
    public let url: URL
    /// Size in bytes, captured at scan time (avoids a stat during cleanup).
    public let size: Int64
    /// Risk classification that governed selection and confirmation routing.
    public let risk: RiskLevel
    /// Bundle identifier of the owning app, when the scanner could attribute it.
    public let bundleID: String?
    /// Scan category identifier this target came from.
    public let categoryID: String?

    public init(id: UUID = UUID(),
                url: URL,
                size: Int64 = 0,
                risk: RiskLevel = .recommended,
                bundleID: String? = nil,
                categoryID: String? = nil) {
        self.id = id
        self.url = url
        self.size = size
        self.risk = risk
        self.bundleID = bundleID
        self.categoryID = categoryID
    }
}

/// How the engine should treat targets that belong to a currently running app.
///
/// Resolved by the warning flow (Task C3 / C6) before cleanup starts.
public enum WarnHandling: String, Sendable, CaseIterable {
    /// Clean everything except the conflicting paths.
    case skip
    /// Terminate the running app, then clean everything.
    case terminate
    /// Cancel the whole cleanup.
    case abort
}

/// Configuration for a single cleanup run.
public struct CleanupConfiguration: Sendable {
    /// What to do about running-app conflicts.
    public let warnHandling: WarnHandling
    /// When `false` the item is deleted outright instead of moved to the trash.
    /// Irreversible — gated behind the DELETE-input dialog (Task C5).
    public let moveToTrash: Bool
    /// Whether to write `CleanupHistoryItem` rows for this run.
    public let recordHistory: Bool
    /// Retention window applied by the post-run lazy purge.
    public let retentionDays: Int

    public init(warnHandling: WarnHandling = .skip,
                moveToTrash: Bool = true,
                recordHistory: Bool = true,
                retentionDays: Int = CleanupHistoryRetention.days) {
        self.warnHandling = warnHandling
        self.moveToTrash = moveToTrash
        self.recordHistory = recordHistory
        self.retentionDays = retentionDays
    }

    /// Default v1.0 behaviour: skip conflicts, trash (recoverable), record history.
    public static let `default` = CleanupConfiguration()
}

// MARK: - Confirmation level

/// 4-level cleanup confirmation routing (v3 spec §2.6).
public enum CleanupConfirmationLevel: Sendable, Equatable {
    /// Only `recommended` + `optional` items → one-tap confirm.
    case low
    /// Includes `caution` items → per-item list confirmation.
    case medium
    /// Includes `dangerous` items or running-app conflicts → warning flow.
    case high
    /// Skip trash (irreversible delete) → user must type DELETE.
    case irreversible

    /// Decide the level from the targets' risk mix and whether any running apps
    /// conflict with the selection.
    public static func from(riskLevels: [RiskLevel], hasWarnItems: Bool) -> CleanupConfirmationLevel {
        if riskLevels.contains(.dangerous) || hasWarnItems { return .high }
        if riskLevels.contains(.caution) { return .medium }
        return .low
    }
}

// MARK: - Cleanup result

/// A target that could not be cleaned, with a human-presentable reason.
public struct CleanupFailure: Sendable, Identifiable {
    public let id: UUID
    public let url: URL
    public let reason: String

    public init(id: UUID = UUID(), url: URL, reason: String) {
        self.id = id
        self.url = url
        self.reason = reason
    }

    public init(url: URL, error: Error) {
        self.init(url: url, reason: error.localizedDescription)
    }
}

/// Outcome of a cleanup run.
public struct CleanupOutcome: Sendable {
    /// URLs successfully moved to the trash (or deleted).
    public let succeeded: [URL]
    /// URLs that failed, each with a reason.
    public let failed: [CleanupFailure]
    /// URLs deliberately left alone because of `WarnHandling.skip`.
    public let skipped: [URL]
    /// Bytes reclaimed, summed over `succeeded`.
    public let freedBytes: Int64

    public init(succeeded: [URL] = [],
                failed: [CleanupFailure] = [],
                skipped: [URL] = [],
                freedBytes: Int64 = 0) {
        self.succeeded = succeeded
        self.failed = failed
        self.skipped = skipped
        self.freedBytes = freedBytes
    }

    /// Number of items successfully cleaned.
    public var successCount: Int { succeeded.count }

    /// `true` when every attempted target succeeded (skipped items do not count as failures).
    public var isFullySuccessful: Bool { failed.isEmpty }

    /// Empty result, used as the initial value and for aborted runs.
    public static let empty = CleanupOutcome()
}
