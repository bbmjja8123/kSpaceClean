// kFoundation/Sources/FileScanner/FileEnumerator.swift
//
// Recursive filesystem walker used by the scan pipeline.
//
// Two public surfaces coexist:
//
// - The original callback-based API (preserved for downstream callers in
//   kSpaceClean that already compile against `enumerate(root:progressHandler:
//   cancellationToken:)` — `ScanResult`, `ScanError`, `CancellationToken`,
//   and `ThrottleConfig`).
//
// - The newer `AsyncStream`-based API used by the v1.0 scan pipeline (B2 +
//   later tasks). It exposes the lightweight `FileInfo` value type and lets
//   consumers consume results lazily via `for await info in stream`.
//
// The walker itself is the same in both cases: a `FileManager` directory
// enumerator with TCC-safe options (skips hidden files + skips package
// descendants) wrapped in a `Task.detached` so it does not block the
// caller's actor.

import Foundation

/// Lightweight description of a single filesystem entry.
///
/// Produced by the ``FileEnumerator`` ``AsyncStream`` overload. Intentionally
/// minimal — the consumer (typically a size aggregator or hash pipeline) only
/// needs the path, on-disk size, modification date, and whether the entry is
/// a directory.
public struct FileInfo: Sendable, Equatable {
    public let path: String
    public let size: Int64
    public let modificationDate: Date?
    public let isDirectory: Bool

    public init(
        path: String,
        size: Int64,
        modificationDate: Date?,
        isDirectory: Bool
    ) {
        self.path = path
        self.size = size
        self.modificationDate = modificationDate
        self.isDirectory = isDirectory
    }
}

public actor FileEnumerator {
    public struct ScanResult: Sendable {
        public let url: URL
        public let size: Int64
        public let isDirectory: Bool

        public init(url: URL, size: Int64, isDirectory: Bool) {
            self.url = url
            self.size = size
            self.isDirectory = isDirectory
        }
    }

    public enum ScanError: Error {
        case cancelled
        case permissionDenied(URL)
    }

    public init() {}

    /// AsyncStream overload (preferred for new code).
    ///
    /// Yields one ``FileInfo`` per visited entry, including directories. The
    /// stream finishes when the walk is exhausted or when ``skipPaths``
    /// short-circuits the entire root.
    ///
    /// `skipPaths` is a set of path prefixes that the walker will refuse to
    /// descend into — the primary use case is excluding other apps' bundle
    /// containers (TCC permission failure on `/Library/Containers/<id>` is
    /// extremely common and would otherwise crash the scan).
    ///
    /// I2 fix: the body runs through ``Self.walk(rootPath:skipPaths:
    /// continuation:)`` which is `nonisolated static`. That lets many
    /// category workers in `ScanOrchestrator` walk different roots in
    /// parallel without serialising on a shared `FileEnumerator` actor —
    /// previously every concurrent scan took a turn through this actor's
    /// mailbox, which collapsed the parallelism the orchestrator was
    /// trying to expose.
    public func enumerate(
        rootPath: String,
        skipPaths: Set<String> = []
    ) -> AsyncStream<FileInfo> {
        AsyncStream(bufferingPolicy: .bufferingNewest(65536)) { continuation in
            Task.detached(priority: .background) {
                await Self.walk(
                    rootPath: rootPath,
                    skipPaths: skipPaths,
                    continuation: continuation
                )
                continuation.finish()
            }
        }
    }

    /// Pure walker — runs as `nonisolated static` so concurrent callers do
    /// not serialise on the `FileEnumerator` actor (I2 fix).
    ///
    /// I3 fix: the stream is now bounded (`bufferingNewest(65536)`) so a
    /// consumer that falls behind does not cause the walker to allocate an
    /// unbounded queue of `FileInfo` values; the stream drops the oldest
    /// entry when full. The bound is sized well above a single scan
    /// category's typical file count so per-file `onProgress` actor hops in
    /// `ScanOrchestrator` cannot starve a category worker (A1 regression).
    /// The walker also honours `Task.isCancelled` and the
    /// `continuation.onTermination` cleanup so a cancellation midway tears
    /// down properly instead of running to completion in the background.
    nonisolated private static func walk(
        rootPath: String,
        skipPaths: Set<String>,
        continuation: AsyncStream<FileInfo>.Continuation
    ) async {
        let normalized = (rootPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: normalized)

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let fileURL as URL in enumerator {
            // Cancellation: drop the loop on the next iteration rather than
            // racing ahead and tearing down the enumerator mid-`for ... in`
            // (which corrupts the FileManager.enumerator state).
            if Task.isCancelled { break }
            // If a skipPath matches the file URL's path, do not descend into
            // its children. `skipDescendants()` advances the enumerator past
            // the entire subtree so the next iteration is the next sibling.
            //
            // We compare against the *standardized* URL path so that an
            // unresolvable symlink (e.g. ``/var/folders/...`` vs the
            // canonical ``/private/var/folders/...`` returned by
            // ``temporaryDirectory``) still matches the caller's prefix.
            let path = fileURL.standardizedFileURL.path
            if skipPaths.contains(where: { path.hasPrefix($0) }) {
                enumerator.skipDescendants()
                continue
            }

            let attrs = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
            )
            let info = FileInfo(
                path: path,
                size: Int64(attrs?.fileSize ?? 0),
                modificationDate: attrs?.contentModificationDate,
                isDirectory: attrs?.isDirectory ?? false
            )
            // `yield` returns a `YieldResult` distinguishing accepted (`.enqueued(remaining:)`)
            // from `dropped` (`.dropped(_)`) when the bounded buffer is full.
            // We ignore the result — the bounded policy is best-effort, not strict.
            _ = continuation.yield(info)
        }
    }

    /// Callback-based overload (preserved for kSpaceClean's scan pipeline).
    ///
    /// Reports only non-directory entries through ``progressHandler``; the
    /// caller receives one `ScanResult` per file. The walk honours
    /// ``CancellationToken`` and throws ``ScanError/cancelled`` if the
    /// caller flips the token mid-walk.
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

/// Cooperative cancellation token consumed by the callback-based
/// ``FileEnumerator/enumerate(root:progressHandler:cancellationToken:)``.
///
/// The token is `final class` (not `actor`) because the only mutation
/// (cancel) is a single boolean flip that does not need isolation; the
/// `@unchecked Sendable` opt-out is the standard pattern for such tokens.
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