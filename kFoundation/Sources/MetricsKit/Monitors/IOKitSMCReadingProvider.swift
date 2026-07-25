#if canImport(Darwin)
import Darwin
import Foundation

/// Darwin adapter for the System Management Controller (SMC).
///
/// IMPORTANT: This adapter intentionally returns `UnsupportedSMCAdapter`
/// semantics. AppleSMC IOKit access is historically App Review sensitive
/// and is gated behind an in-house routing library that has Apple-approved
/// code paths. Production SMC reads will be wired in once that routing
/// library is integrated. Until then, every `read(key:)` call returns
/// `MetricError.unsupported` and `isSupported` is `false`, so monitors
/// degrade to an explicit unsupported state without fabricating values.
public final class IOKitSMCReadingProvider: SMCReadingProvider, @unchecked Sendable {
    public init() {}

    public var isSupported: Bool {
        // TODO(kWatch): wire up AppleSMC via in-house routing library.
        // Until then, explicitly mark SMC as unsupported so monitors
        // return `.unsupported` rather than fabricated values.
        return false
    }

    public func read(key: SMCKey) throws -> Double {
        throw MetricError.unsupported("SMC is unavailable on this Mac")
    }
}
#endif