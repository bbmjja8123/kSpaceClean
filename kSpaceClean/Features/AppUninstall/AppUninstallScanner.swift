import Foundation

// MARK: - Data Model

public struct UninstallAppEntry: Identifiable, Sendable {
    public let id = UUID()
    public let appName: String
    public let bundleID: String
    public let appURL: URL
    public let appSize: Int64
    public var leftoverURLs: [URL]
    public var leftoverSize: Int64
    public var isSelected: Bool = true
    public var totalSize: Int64 { appSize + leftoverSize }
}

// MARK: - Scanner

/// Scans the system for installed `.app` bundles and locates their leftover files
/// in common Library locations.
///
/// This class intentionally uses `@unchecked Sendable` because it wraps
/// `FileManager` (which is not `Sendable` in Swift 5.8) for filesystem
/// enumeration. All public methods are stateless — they produce new values
/// on each call — so the class is safe to use across concurrency domains.
public final class AppUninstallScanner: @unchecked Sendable {

    // MARK: - Public API

    /// Scans standard application directories and returns an array of entries
    /// sorted by total (app + leftover) size descending.
    public func scan() -> [UninstallAppEntry] {
        let appURLs = findAppBundles()
        let entries = appURLs.compactMap { url -> UninstallAppEntry? in
            guard let bundle = Bundle(path: url.path) else { return nil }
            let bundleID = bundle.bundleIdentifier ?? "unknown.\(url.deletingPathExtension().lastPathComponent)"
            let appName = url.deletingPathExtension().lastPathComponent

            let appSize = directorySize(url)
            let leftovers = findLeftovers(bundleID: bundleID, appName: appName)
            let leftoverSize = leftovers.reduce(0) { $0 + directorySize($1) }

            guard appSize > 0 else { return nil }

            return UninstallAppEntry(
                appName: appName,
                bundleID: bundleID,
                appURL: url,
                appSize: appSize,
                leftoverURLs: leftovers,
                leftoverSize: leftoverSize,
                isSelected: true
            )
        }
        return entries.sorted { $0.totalSize > $1.totalSize }
    }

    /// Moves the app bundle and all associated leftover files to the Trash.
    /// - Throws: `TrashError` if any item could not be trashed.
    public func uninstall(entry: UninstallAppEntry) async throws {
        let allURLs = [entry.appURL] + entry.leftoverURLs
        var errors: [URL: Error] = [:]

        for url in allURLs {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            } catch {
                errors[url] = error
            }
        }

        if !errors.isEmpty {
            throw TrashError.failedItems(errors)
        }
    }

    // MARK: - Private Helpers

    /// Returns the URLs of every `.app` bundle found in `/Applications`
    /// and `~/Applications`.
    private func findAppBundles() -> [URL] {
        let fm = FileManager.default
        let scanDirs = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory() + "/Applications", isDirectory: true),
        ]

        var results: [URL] = []
        for dir in scanDirs {
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isApplicationKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: [.isApplicationKey, .isPackageKey]),
                      values.isApplication == true || values.isPackage == true
                else { continue }

                if fileURL.pathExtension.lowercased() == "app" {
                    results.append(fileURL)
                }
            }
        }
        return results
    }

    /// Locates leftover files/directories for a given app in common
    /// Library locations.
    private func findLeftovers(bundleID: String, appName: String) -> [URL] {
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let templates: [(String, String)] = [
            ("Preferences", "\(bundleID).plist"),
            ("Preferences", "\(appName).plist"),
            ("Caches", bundleID),
            ("Caches", appName),
            ("Application Support", bundleID),
            ("Application Support", appName),
            ("Logs", bundleID),
            ("Logs", appName),
            ("Saved Application State", "\(bundleID).savedState"),
            ("Containers", bundleID),
            ("Group Containers", bundleID),
        ]

        var urls: [URL] = []
        for (subdir, lastComponent) in templates {
            let candidate = library
                .appendingPathComponent(subdir, isDirectory: true)
                .appendingPathComponent(lastComponent)
            if FileManager.default.fileExists(atPath: candidate.path) {
                urls.append(candidate)
            }
        }
        return urls
    }

    /// Recursively sums the physical byte size of all files under `url`.
    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else { continue }
            total += Int64(size)
        }
        return total
    }
}

// MARK: - Errors

public enum TrashError: LocalizedError {
    case failedItems([URL: Error])

    public var errorDescription: String? {
        switch self {
        case .failedItems(let dict):
            let count = dict.count
            return "\(count) item(s) could not be moved to Trash."
        }
    }
}
