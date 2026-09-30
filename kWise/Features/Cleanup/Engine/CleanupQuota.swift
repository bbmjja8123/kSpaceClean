// kWise/Features/Cleanup/Engine/CleanupQuota.swift
//
// Buyout gate (P1 T7).
//
// The v2.0 free-quota ledger (1 GiB/month, `FreeQuotaStore`) is retired.
// `CleanupEngine` still consults `CleanupQuotaChecking` before trashing and
// reports every finished run through `CleanupEventSink`, so the menu bar
// "最近清理" row, streaks, the monthly report, and the widget snapshot all
// observe the same events. What changed is the read side: ownership of the
// non-consumable buyout (`app.kraftly.klaris.buyout`) is the only thing
// between the user and a cleanup.
//
// R5 (binding): the unpurchased state is a *refusal*, not a truncation —
// the checker returns 0, the engine moves every selected target to
// `skippedForQuota`, and the run reports `quotaExhausted`, which surfaces
// the paywall. Returning `nil` means unlimited (purchased).
import Foundation

// MARK: - Quota checking

/// Quota gate consulted by `CleanupEngine` before a cleanup run.
///
/// Conformers must be safe to call from the cleanup actor. Returning `nil`
/// means "unlimited" (buyout owned, or the gate disabled in tests).
public protocol CleanupQuotaChecking: Sendable {
    /// Bytes still cleanable, or `nil` when the caller is not limited.
    func remainingFreeBytes() async -> Int64?
}

/// Production gate: the buyout decides. Purchased → `nil` (unlimited);
/// unpurchased → `0` (R5 refusal — everything is skipped, paywall shown).
/// There is no per-month ledger anymore.
public struct CleanupQuotaChecker: CleanupQuotaChecking {
    private let hasPurchased: @Sendable () async -> Bool

    public init(hasPurchased: @escaping @Sendable () async -> Bool) {
        self.hasPurchased = hasPurchased
    }

    public func remainingFreeBytes() async -> Int64? {
        if await hasPurchased() { return nil }
        return 0
    }
}

// MARK: - Cleanup event sink

/// One finished cleanup run, fanned out to every observer.
public struct CleanupEvent: Sendable {
    public let date: Date
    /// Predicted freed bytes (sum of scanned sizes).
    public let freedBytes: Int64
    /// Measured volume delta, when the engine could measure one.
    public let measuredBytes: Int64?
    public let itemCount: Int
    /// `true` when the run was refused by the buyout gate and left targets
    /// behind (field name kept stable — sinks depend on it).
    public let quotaExhausted: Bool

    public init(date: Date = Date(),
                freedBytes: Int64,
                measuredBytes: Int64?,
                itemCount: Int,
                quotaExhausted: Bool = false) {
        self.date = date
        self.freedBytes = freedBytes
        self.measuredBytes = measuredBytes
        self.itemCount = itemCount
        self.quotaExhausted = quotaExhausted
    }
}

/// Observer of finished cleanup runs. Sinks must not throw and must not
/// assume main-actor isolation — the engine calls them from its own actor.
public protocol CleanupEventSink: Sendable {
    func cleanupDidFinish(_ event: CleanupEvent) async
}
