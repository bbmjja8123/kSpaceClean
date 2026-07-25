import Foundation

/// An injectable source of "now", so sampling and history logic can be
/// tested deterministically without touching the wall clock.
public protocol KWatchClock: Sendable {
    func now() -> Date
}

/// The production clock backed by the system wall clock.
public struct SystemClock: KWatchClock {
    public init() {}
    public func now() -> Date { Date() }
}
