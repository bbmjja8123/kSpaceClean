import Foundation

public actor FileEnumerator {
    public struct ScanResult: Sendable {
        public let url: URL
        public let size: Int64
        public let isDirectory: Bool
    }

    public enum ScanError: Error {
        case cancelled
        case permissionDenied(URL)
    }

    public init() {}

    public func enumerate(
        root: URL,
        progressHandler: @Sendable (ScanResult) -> Void,
        cancellationToken: CancellationToken
    ) async throws {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            if cancellationToken.isCancelled { throw ScanError.cancelled }

            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
                  !(values.isDirectory ?? false) else { continue }

            let result = ScanResult(url: url, size: Int64(values.fileSize ?? 0), isDirectory: false)
            progressHandler(result)
        }
    }
}

public final class CancellationToken: @unchecked Sendable {
    public private(set) var isCancelled = false
    public func cancel() { isCancelled = true }

    public init() {}
}

/// Throttle configuration applied during long-running file enumeration so
/// the scanner does not starve the foreground UI.
///
/// A `ThrottleConfig` is derived from ``Features/SmartScan/ScanSpeed.ScanSpeed``
/// in kSpaceClean. The two fields are intentionally trivial (a batch size
/// and a sleep duration) so the value type stays cheap to copy across
/// actor hops; the consumer — `FileEnumerator` — is responsible for
/// actually honouring the throttle.
///
/// ``batchSize`` is the number of files to process before yielding the
/// CPU. `0` means "do not yield at all" (turbo mode).
///
/// ``sleepNanoseconds`` is how long to sleep after each yield. `0` means
/// "yield without sleeping" (so the OS scheduler can pick another
/// task). Non-zero values are useful when the consumer wants a known
/// minimum gap between batches.
public struct ThrottleConfig: Sendable, Equatable {
    public let batchSize: Int
    public let sleepNanoseconds: UInt64

    public init(batchSize: Int, sleepNanoseconds: UInt64) {
        self.batchSize = batchSize
        self.sleepNanoseconds = sleepNanoseconds
    }
}
