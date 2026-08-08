import Foundation
import SwiftUI

/// Thread-safe mirror of `StoreManager.isPaidUser` so non-MainActor contexts
/// (the `ScanOrchestrator` actor and the `IncrementalIndex` actor it owns)
/// can read the current paid status without crossing actor boundaries.
///
/// The main app pumps the latest value in via `set(_:)` whenever the
/// `StoreManager.$isPaidUser` publisher emits; the readers on background
/// actors see the cached value on their next call. Stale-by-one-tick is
/// acceptable — the incremental index is a performance optimization, not
/// a correctness gate.
public final class PaidUserFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool = false

    public init() {}

    public var value: Bool {
        lock.lock(); defer { lock.unlock() }
        return _value
    }

    public func set(_ newValue: Bool) {
        lock.lock(); defer { lock.unlock() }
        _value = newValue
    }
}

/// Environment plumbing for the `PaidUserFlag` mirror so views constructed
/// deep in the tree (e.g. `MainView`) can wire it into the `ScanViewModel`
/// without an explicit prop-drilling chain through `RootView`.
private struct PaidUserFlagEnvironmentKey: EnvironmentKey {
    static let defaultValue: PaidUserFlag? = nil
}

public extension EnvironmentValues {
    var paidUserFlag: PaidUserFlag? {
        get { self[PaidUserFlagEnvironmentKey.self] }
        set { self[PaidUserFlagEnvironmentKey.self] = newValue }
    }
}