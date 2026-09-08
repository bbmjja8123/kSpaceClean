// kWise/Features/Cleanup/Engine/CleanupQuota.swift
//
// Free-tier cleanup quota (v2.0 Phase 1).
//
// CLAUDE.md §3.6 promises a 1 GiB free cleanup allowance. This file is the
// single metering point: `CleanupEngine` consults `CleanupQuotaChecking`
// before trashing and reports every finished run through `CleanupEventSink`,
// so quota accounting, the menu bar "最近清理" row, streaks, the monthly
// report, and the widget snapshot all observe the same events instead of
// each hooking the engine separately.
import Foundation

// MARK: - Quota checking

/// Quota gate consulted by `CleanupEngine` before a cleanup run.
///
/// Conformers must be safe to call from the cleanup actor. Returning `nil`
/// means "unlimited" (subscribed user, or quota disabled in tests).
public protocol CleanupQuotaChecking: Sendable {
    /// Bytes still cleanable in the current free period, or `nil` when the
    /// caller is not quota-limited.
    func remainingFreeBytes() async -> Int64?
}

/// Storage for consumed free-quota bytes.
///
/// Backed by the App Group `UserDefaults` so the widget can render
/// "本周期剩余额度" without a round-trip into the app container. The period
/// is a calendar month (key `quota.<yyyy-MM>`); rollover is therefore
/// predictable and needs no timers.
public struct FreeQuotaStore: Sendable {
    /// Free-tier allowance per period. 1 GiB per CLAUDE.md §3.6.
    public static let freeQuotaBytes: Int64 = 1_073_741_824

    public let defaults: UserDefaults?

    /// - Parameter defaults: pass an App Group suite (`group.app.kraftly.sclean`);
    ///   `nil` defaults are tolerated (tests, extensions without the group) and
    ///   degrade to "nothing recorded".
    public init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    /// App Group defaults for production use.
    public static func standard() -> FreeQuotaStore {
        FreeQuotaStore(defaults: UserDefaults(suiteName: "group.app.kraftly.sclean"))
    }

    /// Current period key, e.g. `"2026-09"`.
    public static func periodKey(for date: Date = Date(),
                                 calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private func key(for date: Date) -> String { "quota.\(Self.periodKey(for: date))" }

    /// Accumulate freed bytes onto the current period.
    public func recordFreed(_ bytes: Int64, now: Date = Date()) {
        guard bytes > 0, let defaults else { return }
        let key = key(for: now)
        let existing = Int64(defaults.integer(forKey: key))
        defaults.set(Int(existing + bytes), forKey: key)
    }

    /// Bytes consumed in the period containing `now`.
    public func consumedBytes(now: Date = Date()) -> Int64 {
        guard let defaults else { return 0 }
        return Int64(defaults.integer(forKey: key(for: now)))
    }

    /// Remaining allowance in the period containing `now` (never negative).
    public func remainingBytes(now: Date = Date()) -> Int64 {
        max(0, Self.freeQuotaBytes - consumedBytes(now: now))
    }

    /// Test/调试 hook — clears the current period's counter.
    public func reset(now: Date = Date()) {
        defaults?.removeObject(forKey: key(for: now))
    }
}

/// Production quota checker: subscribed users are unlimited; free users get
/// the `FreeQuotaStore` allowance.
public struct CleanupQuotaChecker: CleanupQuotaChecking {
    private let isSubscribed: @Sendable () async -> Bool
    private let store: FreeQuotaStore

    public init(store: FreeQuotaStore = .standard(),
                isSubscribed: @escaping @Sendable () async -> Bool) {
        self.store = store
        self.isSubscribed = isSubscribed
    }

    public func remainingFreeBytes() async -> Int64? {
        if await isSubscribed() { return nil }
        return store.remainingBytes()
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
    /// `true` when the run hit the free-quota ceiling and left targets behind.
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

/// Sink that feeds freed bytes back into the free-quota ledger. Recording is
/// unconditional; the *read* side (`CleanupQuotaChecker`) ignores the ledger
/// for subscribed users, so Pro users never consume quota.
public struct QuotaRecordSink: CleanupEventSink {
    private let store: FreeQuotaStore

    public init(store: FreeQuotaStore = .standard()) {
        self.store = store
    }

    public func cleanupDidFinish(_ event: CleanupEvent) async {
        store.recordFreed(event.freedBytes, now: event.date)
    }
}
