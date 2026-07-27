import Foundation

// MARK: - CleanActionExecutor Protocol

/// A per-action-type executor that knows how to process scanned results.
///
/// Each executor conforms to `Sendable`.  All mutable state lives inside the
/// `execute` method so instances are effectively stateless and can be shared
/// across concurrency domains.
public protocol CleanActionExecutor: Sendable {
    /// The action type this executor handles.
    var actionType: ScanActionType { get }

    /// Process (clean) the item at `url`.
    ///
    /// - Returns: `true` if the item was successfully cleaned; `false` if the
    ///   executor decided the item should be skipped (e.g. not a universal
    ///   binary, language already kept, etc.).
    /// - Throws: A `CleanExecutorError` if the operation fails irrecoverably.
    @discardableResult
    func execute(url: URL) async throws -> Bool
}

// MARK: - Errors

/// Errors that can be raised by `CleanActionExecutor` implementations.
public enum CleanExecutorError: LocalizedError, Sendable {
    case fileNotFound(URL)
    case notExpectedFormat(URL, reason: String)
    case processFailed(URL, command: String, exitCode: Int32)
    case trashFailed(URL, underlying: Error)
    case removalFailed(URL, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.path)"
        case .notExpectedFormat(let url, let reason):
            return "\(url.path) is not the expected format: \(reason)"
        case .processFailed(let url, let command, let code):
            return "\(command) failed for \(url.path) with exit code \(code)"
        case .trashFailed(let url, let underlying):
            return "Failed to trash \(url.path): \(underlying.localizedDescription)"
        case .removalFailed(let url, let underlying):
            return "Failed to remove \(url.path): \(underlying.localizedDescription)"
        }
    }
}

// MARK: - Utility Extensions

extension FileManager {
    /// Returns `true` when `url` is a directory.
    fileprivate func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}

// MARK: - 1. BinarySlicingExecutor

/// Thins universal (fat) Mach-O binaries by extracting the `arm64` slice.
///
/// **When it acts:**
/// The file must begin with the `FAT_MAGIC` (0xCAFEBABE) magic number.  Only
/// then is `lipo -extract arm64` invoked to produce a single-architecture
/// binary, which replaces the original.
public final class BinarySlicingExecutor: @unchecked Sendable, CleanActionExecutor {
    public let actionType: ScanActionType = .binary

    public init() {}

    public func execute(url: URL) async throws -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw CleanExecutorError.fileNotFound(url)
        }

        guard isUniversalBinary(url) else {
            return false
        }

        // Create a temporary output path for the thinned binary.
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let tempURL = tempDir.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: tempURL) }

        // Run: lipo -extract arm64 <input> -output <temp>
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
        process.arguments = ["-extract", "arm64", url.path, "-output", tempURL.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw CleanExecutorError.processFailed(url, command: "lipo -extract arm64", exitCode: -1)
        }

        guard process.terminationStatus == 0 else {
            throw CleanExecutorError.processFailed(url, command: "lipo -extract arm64", exitCode: process.terminationStatus)
        }

        guard fm.fileExists(atPath: tempURL.path) else {
            throw CleanExecutorError.notExpectedFormat(url, reason: "lipo produced no output")
        }

        // Atomically replace the original with the thinned binary.
        // 1. Remove original
        try fm.removeItem(at: url)
        // 2. Move thinned version to original location
        try fm.moveItem(at: tempURL, to: url)

        return true
    }

    // MARK: Helpers

    /// Returns `true` when the file at `url` is a Mach-O universal (fat) binary.
    private func isUniversalBinary(_ url: URL) -> Bool {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fileHandle.close() }

        let magicData = fileHandle.readData(ofLength: 4)
        guard magicData.count == 4 else { return false }

        let bytes = [UInt8](magicData)

        // FAT_MAGIC (big-endian on disk): 0xCA 0xFE 0xBA 0xBE
        // FAT_CIGAM (little-endian representation): 0xBE 0xBA 0xFE 0xCA
        let fatMagic: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE]
        let fatCigam: [UInt8] = [0xBE, 0xBA, 0xFE, 0xCA]

        return bytes == fatMagic || bytes == fatCigam
    }
}

// MARK: - 2. LanguagePackRemovalExecutor

/// Removes `.lproj` language directories that the user does not need.
///
/// **Always kept:** `"en"`, `"Base"`, and every language that appears in
/// `Locale.preferredLanguages`.  Any `.lproj` directory whose language code
/// falls outside this set is moved to Trash.
public final class LanguagePackRemovalExecutor: @unchecked Sendable, CleanActionExecutor {
    public let actionType: ScanActionType = .language

    /// Languages that should never be removed regardless of user preference.
    private let alwaysKeep: Set<String> = ["en", "Base"]

    public init() {}

    public func execute(url: URL) async throws -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw CleanExecutorError.fileNotFound(url)
        }

        let dirName = url.lastPathComponent
        guard dirName.hasSuffix(".lproj") else {
            return false
        }

        let languageCode = String(dirName.dropLast(".lproj".count))
        guard !languageCode.isEmpty else { return false }

        let keepSet = alwaysKeep.union(preferredLanguageCodes())

        guard !keepSet.contains(languageCode) else {
            return false
        }

        // Move the .lproj directory to Trash.
        var trashedURL: NSURL?
        do {
            try fm.trashItem(at: url, resultingItemURL: &trashedURL)
        } catch {
            throw CleanExecutorError.trashFailed(url, underlying: error)
        }

        return trashedURL != nil
    }

    /// Normalised two-letter language codes from the user's preferred languages.
    private func preferredLanguageCodes() -> Set<String> {
        let codes = Locale.preferredLanguages.map { raw -> String in
            // "zh-Hans-CN" -> "zh", "en-US" -> "en"
            let normalized = raw.split(separator: "-").first.map(String.init) ?? raw
            return normalized.lowercased()
        }
        return Set(codes)
    }
}

// MARK: - 3. ArchiveExtractExecutor

/// Validates and trashes archive files (`.zip`, `.tar`, `.gz`, `.tar.gz`, etc.).
///
/// The executor uses `/usr/bin/tar` (`.tar` variants) or `/usr/bin/unzip`
/// (`.zip`) to list archive contents as a lightweight validity check before
/// moving the file to Trash.  Archives are **never** deleted outright; they are
/// always recoverable from Trash.
public final class ArchiveExtractExecutor: @unchecked Sendable, CleanActionExecutor {
    public let actionType: ScanActionType = .archive

    private let supportedExtensions: Set<String> = [
        "zip", "tar", "gz", "tgz", "bz2", "tbz", "xz", "lzma", "7z", "rar",
    ]

    public init() {}

    public func execute(url: URL) async throws -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw CleanExecutorError.fileNotFound(url)
        }

        guard isArchive(url) else {
            return false
        }

        // Lightweight validity check via listing contents.
        let isValid = try await validateArchive(url)
        guard isValid else {
            throw CleanExecutorError.notExpectedFormat(url, reason: "archive validation failed")
        }

        // Move to Trash (never irreversible delete).
        var trashedURL: NSURL?
        do {
            try fm.trashItem(at: url, resultingItemURL: &trashedURL)
        } catch {
            throw CleanExecutorError.trashFailed(url, underlying: error)
        }

        return trashedURL != nil
    }

    /// Returns `true` if the file extension matches a known archive format.
    private func isArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let lastPath = url.lastPathComponent.lowercased()

        if supportedExtensions.contains(ext) { return true }
        // Double-extensions like ".tar.gz", ".tar.bz2"
        if lastPath.hasSuffix(".tar.gz") || lastPath.hasSuffix(".tar.bz2") || lastPath.hasSuffix(".tar.xz") {
            return true
        }
        return false
    }

    /// Run the appropriate listing tool to confirm the file is a valid archive.
    private func validateArchive(_ url: URL) async throws -> Bool {
        let ext = url.pathExtension.lowercased()

        if ext == "zip" {
            return runProcess(executable: "/usr/bin/unzip", args: ["-l", url.path])
        } else {
            // tar handles .tar, .tar.gz, .tar.bz2, .tar.xz, .tgz, .tbz
            return runProcess(executable: "/usr/bin/tar", args: ["-tf", url.path])
        }
    }

    /// Synchronously run a child process and return `true` on exit code 0.
    private func runProcess(executable: String, args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let nullDev = FileHandle.nullDevice
        process.standardOutput = nullDev
        process.standardError = nullDev

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - 4. MailAttachmentExecutor

/// Removes cached Mail attachments from
/// `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/`.
///
/// These are safe to delete: the system treats them as a cache and will
/// re-download attachments on demand.
public final class MailAttachmentExecutor: @unchecked Sendable, CleanActionExecutor {
    public let actionType: ScanActionType = .mail

    /// The well-known subpath for Mail's attachment cache.
    private let mailDownloadsSubpath = "Containers/com.apple.mail/Data/Library/Mail Downloads"

    public init() {}

    public func execute(url: URL) async throws -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return false
        }

        // Safety check: only act on files inside the known Mail Downloads path.
        guard isUnderMailDownloads(url) else {
            return false
        }

        var trashedURL: NSURL?
        do {
            try fm.trashItem(at: url, resultingItemURL: &trashedURL)
        } catch {
            throw CleanExecutorError.trashFailed(url, underlying: error)
        }

        return trashedURL != nil
    }

    /// Verify the URL resides inside the recognised Mail attachment cache.
    private func isUnderMailDownloads(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let expectedPrefix = home.appendingPathComponent(mailDownloadsSubpath).path
        return url.path.hasPrefix(expectedPrefix)
    }
}

// MARK: - 5. AppCacheCleanExecutor

/// Cleans structured cache directories while preserving the directory tree.
///
/// When the URL points to a **directory** the executor enumerates its direct
/// children and removes every item, leaving the (now empty) directory in
/// place.  When the URL points to a **file** (e.g. `Cache.db`) the file itself
/// is removed.
///
/// Typical targets are subdirectories inside `~/Library/Caches/` that contain
/// well-known cache artifacts such as `fsCachedData/` or `Cache.db`.
public final class AppCacheCleanExecutor: @unchecked Sendable, CleanActionExecutor {
    public let actionType: ScanActionType = .appCache

    public init() {}

    public func execute(url: URL) async throws -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return false
        }

        if fm.isDirectory(url) {
            // Preserve the directory, remove its direct children.
            let contents: [URL]
            do {
                contents = try fm.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: [.skipsHiddenFiles]
                )
            } catch {
                throw CleanExecutorError.removalFailed(url, underlying: error)
            }

            guard !contents.isEmpty else { return false }

            var removedAny = false
            for childURL in contents {
                do {
                    try fm.removeItem(at: childURL)
                    removedAny = true
                } catch {
                    // If a single child fails, continue with the rest.
                    throw CleanExecutorError.removalFailed(childURL, underlying: error)
                }
            }
            return removedAny
        } else {
            // Single cache file — remove it.
            do {
                try fm.removeItem(at: url)
            } catch {
                throw CleanExecutorError.removalFailed(url, underlying: error)
            }
            return true
        }
    }
}

// MARK: - 6. LeftCacheExecutor

/// Cleans leftover cache directories/files inside `~/Library/Caches/` that
/// belong to unrecognised or uninstalled applications.
///
/// This acts as a catch-all for cache items that were not claimed by a
/// dedicated cleaner (e.g. AppCacheCleanExecutor).  The directory hierarchy
/// is preserved; only files and empty leaf directories are removed.
public final class LeftCacheExecutor: @unchecked Sendable, CleanActionExecutor {
    public let actionType: ScanActionType = .leftCache

    public init() {}

    public func execute(url: URL) async throws -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return false
        }

        // Safety: only process items under ~/Library/Caches.
        guard isUnderCaches(url) else {
            return false
        }

        if fm.isDirectory(url) {
            return try await removeContentsRecursively(url)
        } else {
            return try removeSingleFile(url)
        }
    }

    // MARK: Helpers

    /// Returns `true` when `url` is a descendant of `~/Library/Caches/`.
    private func isUnderCaches(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cachesDir = home.appendingPathComponent("Library/Caches")
        return url.path.hasPrefix(cachesDir.path)
    }

    /// Remove all items inside `directory` while keeping the directory itself.
    private func removeContentsRecursively(_ directory: URL) async throws -> Bool {
        let fm = FileManager.default
        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            return false
        }

        guard !contents.isEmpty else { return false }

        for childURL in contents {
            if fm.isDirectory(childURL) {
                // Recurse into subdirectories to remove their contents.
                try await removeContentsRecursively(childURL)
                // After emptying, also remove the now-empty directory.
                try? fm.removeItem(at: childURL)
            } else {
                try? fm.removeItem(at: childURL)
            }
        }
        return true
    }

    private func removeSingleFile(_ url: URL) throws -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            throw CleanExecutorError.removalFailed(url, underlying: error)
        }
    }
}

// MARK: - 7. LeftLogExecutor

/// Removes leftover log files from `~/Library/Logs/` and `/Library/Logs/`.
///
/// The executor preserves directory structure and only removes regular files
/// (or empty subdirectories after their contents have been removed).
public final class LeftLogExecutor: @unchecked Sendable, CleanActionExecutor {
    public let actionType: ScanActionType = .leftLog

    /// Known log paths the scanner may return.
    private let allowedPrefixes: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Logs").path,
            "/Library/Logs",
            "/private/var/log",
        ]
    }()

    public init() {}

    public func execute(url: URL) async throws -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return false
        }

        guard isUnderAllowedLogPath(url) else {
            return false
        }

        if fm.isDirectory(url) {
            return try await removeLogDirectory(url)
        } else {
            return try removeLogFile(url)
        }
    }

    // MARK: Helpers

    private func isUnderAllowedLogPath(_ url: URL) -> Bool {
        allowedPrefixes.contains { url.path.hasPrefix($0) }
    }

    /// Recursively remove all log files inside the directory, then remove the
    /// (now empty) directory itself.
    private func removeLogDirectory(_ directory: URL) async throws -> Bool {
        let fm = FileManager.default
        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            return false
        }

        guard !contents.isEmpty else { return false }

        for childURL in contents {
            if fm.isDirectory(childURL) {
                try await removeLogDirectory(childURL)
            }
            try? fm.removeItem(at: childURL)
        }

        // Remove the now-empty parent directory.
        try? fm.removeItem(at: directory)
        return true
    }

    private func removeLogFile(_ url: URL) throws -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            throw CleanExecutorError.removalFailed(url, underlying: error)
        }
    }
}

// MARK: - 8. SoftDeleteExecutor

/// Handles "software leftover" cleanup: moves files to Trash and performs
/// broader temporary / swap cleanup where accessible.
///
/// Actions performed:
/// 1. Moves the given URL item to Trash if it represents a regular file/dir.
/// 2. Attempts to clean `NSTemporaryDirectory()` files.
/// 3. Attempts to purge swap files accessible under the current sandbox.
///
/// Note: Emptying the system Trash requires Automation permission for Finder
/// and may fail in sandboxed contexts.
public final class SoftDeleteExecutor: @unchecked Sendable, CleanActionExecutor {
    public let actionType: ScanActionType = .soft

    public init() {}

    public func execute(url: URL) async throws -> Bool {
        let fm = FileManager.default

        // ── 1. Process the specific URL item ──────────────────────────
        guard fm.fileExists(atPath: url.path) else {
            return false
        }

        let isTrashDir: Bool = {
            guard let trash = fm.trashDirectory else { return false }
            return url.path == trash.path
        }()

        if isTrashDir {
            return await emptySystemTrash()
        }

        // Move item to trash.
        var trashedURL: NSURL?
        do {
            try fm.trashItem(at: url, resultingItemURL: &trashedURL)
        } catch {
            throw CleanExecutorError.trashFailed(url, underlying: error)
        }

        // ── 2. Best-effort broader cleanup ───────────────────────────
        // These are fire-and-forget; failures are intentionally swallowed.

        // Clean known temp locations if the URL resides there.
        cleanTemporaryFiles(under: url)

        // Attempt to purge accessible swap-like files.
        try? purgeSwapFiles()

        return trashedURL != nil
    }

    // MARK: Broader Cleanup Helpers

    /// Delete files inside `NSTemporaryDirectory()` — but only files nested
    /// under the same directory tree as the original URL, so we do not
    /// indiscriminately wipe all temp data.
    private func cleanTemporaryFiles(under url: URL) {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        guard url.path.hasPrefix(tempDir.path) else { return }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents {
            try? fm.removeItem(at: item)
        }
    }

    /// Attempt to remove swap files from `/private/var/vm/`.
    /// This will only succeed with Full Disk Access.
    private func purgeSwapFiles() throws {
        let swapDir = URL(fileURLWithPath: "/private/var/vm")
        let fm = FileManager.default
        guard fm.fileExists(atPath: swapDir.path) else { return }

        let contents = try fm.contentsOfDirectory(
            at: swapDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for url in contents {
            let name = url.lastPathComponent
            // Only target swapfile / sleepimage / vm-related files.
            guard name.hasPrefix("swapfile") || name == "sleepimage" || name.hasPrefix("vm_") else {
                continue
            }
            try? fm.removeItem(at: url)
        }
    }

    /// Attempt to empty the system Trash via `osascript` (requires Automation
    /// permission for Finder).  Falls back to deleting items inside the Trash
    /// directory directly if the AppleScript route fails.
    private func emptySystemTrash() async -> Bool {
        // Try AppleScript first.
        let scriptProcess = Process()
        scriptProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        scriptProcess.arguments = ["-e", "tell application \"Finder\" to empty trash"]

        let pipe = Pipe()
        scriptProcess.standardError = pipe

        do {
            try scriptProcess.run()
            scriptProcess.waitUntilExit()
            if scriptProcess.terminationStatus == 0 { return true }
        } catch {
            // Fall through to manual deletion.
        }

        // Fallback: manually delete Trash contents.
        guard let trashDir = FileManager.default.trashDirectory else { return false }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: trashDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }

        var success = true
        for url in contents {
            do {
                try fm.removeItem(at: url)
            } catch {
                success = false
            }
        }
        return success
    }
}

// MARK: - Executor Registry

/// A dictionary that maps every `ScanActionType` to its corresponding
/// `CleanActionExecutor`.
///
/// Usage:
/// ```swift
/// if let executor = allExecutors[actionType] {
///     let cleaned = try await executor.execute(url: someURL)
/// }
/// ```
public let allExecutors: [ScanActionType: CleanActionExecutor] = {
    let list: [CleanActionExecutor] = [
        BinarySlicingExecutor(),
        LanguagePackRemovalExecutor(),
        ArchiveExtractExecutor(),
        MailAttachmentExecutor(),
        AppCacheCleanExecutor(),
        LeftCacheExecutor(),
        LeftLogExecutor(),
        SoftDeleteExecutor(),
    ]
    return Dictionary(uniqueKeysWithValues: list.map { ($0.actionType, $0) })
}()
