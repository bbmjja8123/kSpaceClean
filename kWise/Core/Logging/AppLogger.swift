import Foundation
import os

/// Unified logging facade over `os.Logger`.
///
/// Categories map to product surfaces so Console.app filtering is useful:
/// `scan`, `cleanup`, `privacy`, `store`, `ui`, `galaxy`. All previous
/// `print()` call sites route through here; `print(` is banned in the app
/// target by SwiftLint custom rules.
public struct AppLogger: Sendable {

    public enum Category: String, Sendable, CaseIterable {
        case scan, cleanup, privacy, store, ui, galaxy
    }

    public let category: Category
    private let logger: Logger

    public init(_ category: Category) {
        self.category = category
        self.logger = Logger(subsystem: "app.kraftly.sclean", category: category.rawValue)
    }

    public func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    /// Default level — use for expected-but-notable events.
    public func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    public func fault(_ message: String) {
        logger.fault("\(message, privacy: .public)")
    }

    // MARK: - Perf signposts

    /// Interval signposter (Instruments: Points of Interest).
    public func signposter() -> OSSignposter {
        OSSignposter(subsystem: "app.kraftly.sclean", category: category.rawValue)
    }
}

/// Shared loggers — construct once, pass down where isolation matters.
public enum Log {
    public static let scan = AppLogger(.scan)
    public static let cleanup = AppLogger(.cleanup)
    public static let privacy = AppLogger(.privacy)
    public static let store = AppLogger(.store)
    public static let ui = AppLogger(.ui)
    public static let galaxy = AppLogger(.galaxy)
}
