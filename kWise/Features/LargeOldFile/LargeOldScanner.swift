import Foundation

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

// MARK: - Scanner

/// Two-phase scanner that finds files above a size threshold.
///
/// **Phase 1** runs `mdfind -onlyin <path> "kMDItemFSSize > N"` to leverage Spotlight,
/// which is dramatically faster than walking the file system from scratch.
///
/// **Phase 2** enumerates the same paths via `FileManager.enumerator` as a fallback
/// (Spotlight excludes certain locations such as `~/Library/Caches/` for some users).
///
/// Results are deduplicated and streamed through an `AsyncStream`.
public final class LargeOldScanner: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Starts a scan.
    ///
    /// - Parameter config: Scan parameters (size threshold, age filter, root paths).
    /// - Returns: An `AsyncStream` of `LargeOldFileEntry`. Order is unspecified.
    public func scan(config: LargeOldScanConfig) -> AsyncStream<LargeOldFileEntry> {
        AsyncStream { continuation in
            Task.detached(priority: .userInitiated) { [fileManager] in
                var seen: Set<String> = []

                // Phase 1: Spotlight
                let spotlight = await Self.runMDFind(config: config)
                for entry in spotlight where !seen.contains(entry.path) {
                    seen.insert(entry.path)
                    continuation.yield(entry)
                }

                // Phase 2: Manual fallback
                let manual = await Self.runFileSystem(config: config, fileManager: fileManager)
                for entry in manual where !seen.contains(entry.path) {
                    seen.insert(entry.path)
                    continuation.yield(entry)
                }

                continuation.finish()
            }
        }
    }

    // MARK: - Phase 1: Spotlight (mdfind)

    private static func runMDFind(config: LargeOldScanConfig) async -> [LargeOldFileEntry] {
        var all: [LargeOldFileEntry] = []
        for root in config.scanPaths {
            let paths = await runMDFind(scope: root, minSize: config.minFileSize)
            for path in paths {
                guard let entry = entryFromPath(path, config: config) else { continue }
                all.append(entry)
            }
        }
        return all
    }

    private static func runMDFind(scope: URL, minSize: Int64) async -> [String] {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            process.arguments = [
                "-onlyin", scope.path,
                "kMDItemFSSize > \(minSize)"
            ]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                continuation.resume(returning: [])
                return
            }

            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let lines = output
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init)
            continuation.resume(returning: lines)
        }
    }

    // MARK: - Phase 2: File system walk

    private static func runFileSystem(
        config: LargeOldScanConfig,
        fileManager: FileManager
    ) async -> [LargeOldFileEntry] {
        var all: [LargeOldFileEntry] = []

        for root in config.scanPaths {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .fileSizeKey,
                    .contentModificationDateKey,
                    .creationDateKey,
                    .contentAccessDateKey,
                    .isRegularFileKey
                ],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: Set([
                    .isRegularFileKey, .fileSizeKey, .contentModificationDateKey
                ])),
                      values.isRegularFile == true,
                      let size = values.fileSize,
                      Int64(size) >= config.minFileSize
                else { continue }

                let modDate = values.contentModificationDate ?? Date.distantPast
                if let age = config.minFileAge,
                   Date().timeIntervalSince(modDate) < age {
                    continue
                }

                let creation = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
                let access = (try? url.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate)

                all.append(LargeOldFileEntry(
                    url: url,
                    size: Int64(size),
                    modificationDate: modDate,
                    creationDate: creation,
                    lastAccessDate: access
                ))
            }
        }

        return all
    }

    // MARK: - Path → Entry

    private static func entryFromPath(_ path: String, config: LargeOldScanConfig) -> LargeOldFileEntry? {
        let url = URL(fileURLWithPath: path)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64,
              size >= config.minFileSize
        else { return nil }

        let modDate = attrs[.modificationDate] as? Date ?? Date.distantPast
        if let age = config.minFileAge,
           Date().timeIntervalSince(modDate) < age {
            return nil
        }

        return LargeOldFileEntry(
            url: url,
            size: size,
            modificationDate: modDate,
            creationDate: attrs[.creationDate] as? Date,
            lastAccessDate: nil
        )
    }
}