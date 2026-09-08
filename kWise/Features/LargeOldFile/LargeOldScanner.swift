import Foundation
import CommonUtils
import DetectionCore

// MARK: - Configuration

/// User-configurable parameters for a large/old file scan.
public struct LargeOldScanConfig: Sendable, Equatable {
    /// Minimum file size in bytes. Default 50 MB.
    public var minFileSize: Int64

    /// Optional age filter — only files older than `minFileAge` seconds are kept.
    public var minFileAge: TimeInterval?

    /// Root paths to scan. Defaults to `~/`.
    public var scanPaths: [URL]

    /// Skip files belonging to system locations where writes are restricted.
    public var skipSystemFiles: Bool

    public init(
        minFileSize: Int64 = 50 * 1024 * 1024,
        minFileAge: TimeInterval? = nil,
        scanPaths: [URL] = [URL(fileURLWithPath: NSHomeDirectory())],
        skipSystemFiles: Bool = true
    ) {
        self.minFileSize = minFileSize
        self.minFileAge = minFileAge
        self.scanPaths = scanPaths
        self.skipSystemFiles = skipSystemFiles
    }
}

// MARK: - Entry

/// A single large or old file discovered by the scanner.
public struct LargeOldFileEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let url: URL
    public let size: Int64
    public let modificationDate: Date
    public let creationDate: Date?
    public let lastAccessDate: Date?
    public let fileName: String
    public let path: String
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        size: Int64,
        modificationDate: Date,
        creationDate: Date? = nil,
        lastAccessDate: Date? = nil,
        fileName: String? = nil,
        path: String? = nil,
        isSelected: Bool = false
    ) {
        self.id = id
        self.url = url
        self.size = size
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.lastAccessDate = lastAccessDate
        self.fileName = fileName ?? url.lastPathComponent
        self.path = path ?? url.path
        self.isSelected = isSelected
    }
}

// MARK: - Scanner (DetectionCore adapter)

/// Large/old file scanner backed by the DetectionCore engine (kSift's
/// `FileWalker` + `LargeFileDetector`).
///
/// The old implementation spawned `/usr/bin/mdfind` — a child process the
/// App Sandbox cannot launch (it either failed silently or lied, C-5) —
/// plus a redundant second walk. The engine swap keeps the same
/// `scan(config:) -> AsyncStream<LargeOldFileEntry>` UI contract; only the
/// age filter is applied app-side after the detector returns.
public final class LargeOldScanner: @unchecked Sendable {

    public init() {}

    /// Starts a scan.
    ///
    /// - Parameter config: Scan parameters (size threshold, age filter, root paths).
    /// - Returns: An `AsyncStream` of `LargeOldFileEntry`, sorted size-descending.
    public func scan(config: LargeOldScanConfig) -> AsyncStream<LargeOldFileEntry> {
        AsyncStream { continuation in
            Task.detached(priority: .userInitiated) {
                let controller = ScanController()
                let walker = FileWalker()
                let target = ScanTarget(
                    directories: config.scanPaths.map(\.path),
                    exclusions: [],
                    minFileSize: config.minFileSize
                )

                let urls: [URL]
                do {
                    urls = try await walker.walk(target: target, controller: controller) { _ in }
                } catch {
                    continuation.finish()
                    return
                }

                let detected = await LargeFileDetector(threshold: config.minFileSize)
                    .detect(urls, controller: controller)

                let now = Date()
                let entries: [LargeOldFileEntry] = detected
                    .compactMap { item -> LargeOldFileEntry? in
                        let modDate = item.modificationDate ?? Date.distantPast
                        if let age = config.minFileAge,
                           now.timeIntervalSince(modDate) < age {
                            return nil
                        }
                        return LargeOldFileEntry(
                            url: item.url,
                            size: item.size,
                            modificationDate: modDate,
                            creationDate: item.creationDate
                        )
                    }
                    .sorted { $0.size > $1.size }

                for entry in entries {
                    continuation.yield(entry)
                }
                continuation.finish()
            }
        }
    }
}
