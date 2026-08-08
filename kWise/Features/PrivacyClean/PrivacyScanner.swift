import Foundation

// MARK: - PrivacyItem

public struct PrivacyItem: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let category: PrivacyCategory
    public let url: URL
    public let estimatedSize: Int64
    public var isSelected: Bool = true

    public enum PrivacyCategory: String, Sendable, CaseIterable {
        case safari = "Safari"
        case chrome = "Chrome"
        case firefox = "Firefox"
        case quickLook = "Quick Look"
        case recentItems = "最近项目"
        case downloadHistory = "下载记录"
        case systemLogs = "系统日志"

        /// Default sort order: browsers first, then system items, then logs.
        public static let displayOrder: [PrivacyCategory] = [
            .safari, .chrome, .firefox,
            .quickLook, .recentItems, .downloadHistory,
            .systemLogs,
        ]

        public var icon: String {
            switch self {
            case .safari:          return "safari"
            case .chrome:          return "globe"
            case .firefox:         return "flame"
            case .quickLook:       return "eye"
            case .recentItems:     return "clock.arrow.circlepath"
            case .downloadHistory: return "arrow.down.circle"
            case .systemLogs:      return "doc.text.magnifyingglass"
            }
        }

        public var color: String {
            switch self {
            case .safari:          return "blue"
            case .chrome:          return "green"
            case .firefox:         return "orange"
            case .quickLook:       return "purple"
            case .recentItems:     return "teal"
            case .downloadHistory: return "indigo"
            case .systemLogs:      return "gray"
            }
        }
    }
}

// MARK: - PrivacyScanner

/// Scans the user's home directory for browser history, cookies, caches,
/// Quick Look thumbnails, recent-items plists, download history, and old
/// system logs.  Every computed property is `Sendable`; the scanner holds
/// no mutable state, so it is safe to call from any isolation domain.
public final class PrivacyScanner: Sendable {
    private let fm = FileManager.default
    private let home: URL

    public init() {
        home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    // MARK: - Public API

    /// Synchronous scan -- performs I/O on the calling thread.  Callers
    /// should wrap this in `Task.detached { … }` to avoid blocking the
    /// main actor.
    public func scan() -> [PrivacyItem] {
        var items: [PrivacyItem] = []

        items.append(contentsOf: scanSafari())
        items.append(contentsOf: scanChrome())
        items.append(contentsOf: scanFirefox())
        items.append(contentsOf: scanQuickLook())
        items.append(contentsOf: scanRecentItems())
        items.append(contentsOf: scanDownloadHistory())
        items.append(contentsOf: scanSystemLogs())

        return items
    }

    /// Moves every URL in `items` to the Trash.
    /// - Returns: The number of items successfully trashed.
    public func cleanup(items: [PrivacyItem]) async -> Int {
        var successCount = 0
        for item in items {
            guard fm.fileExists(atPath: item.url.path) else { continue }
            do {
                var trashedURL: NSURL?
                try fm.trashItem(at: item.url, resultingItemURL: &trashedURL)
                successCount += 1
            } catch {
                // Silently skip items that cannot be trashed (e.g. permission
                // denied, file in use).  The caller may inspect the returned
                // count to show a partial-success notice.
                continue
            }
        }
        return successCount
    }

    // MARK: - Safari

    private func scanSafari() -> [PrivacyItem] {
        let safari = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Safari")
        guard directoryExists(safari) else { return [] }

        var items: [PrivacyItem] = []

        // History.db
        let history = safari.appendingPathComponent("History.db")
        appendIfExists(&items, url: history, name: "浏览历史 (History.db)",
                       category: .safari)

        // Cookies.db
        let cookies = safari.appendingPathComponent("Cookies.db")
        appendIfExists(&items, url: cookies, name: "Cookie (Cookies.db)",
                       category: .safari)

        // LocalStorage/
        let localStorage = safari.appendingPathComponent("LocalStorage")
        appendIfExists(&items, url: localStorage, name: "本地存储 (LocalStorage)",
                       category: .safari)

        return items
    }

    // MARK: - Chrome

    private func scanChrome() -> [PrivacyItem] {
        let chrome = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Google")
            .appendingPathComponent("Chrome")
        guard directoryExists(chrome) else { return [] }

        var items: [PrivacyItem] = []

        // Scan each profile directory (Default, Profile 1, …)
        let profileDirs = chrome.profileDirectories(fm: fm)
        for profile in profileDirs {
            let history = profile.appendingPathComponent("History")
            appendIfExists(&items, url: history,
                           name: "\(profile.lastPathComponent) 浏览历史",
                           category: .chrome)

            let cookies = profile.appendingPathComponent("Cookies")
            appendIfExists(&items, url: cookies,
                           name: "\(profile.lastPathComponent) Cookie",
                           category: .chrome)

            let cache = profile.appendingPathComponent("Cache")
            appendIfExists(&items, url: cache,
                           name: "\(profile.lastPathComponent) 缓存",
                           category: .chrome)
        }

        return items
    }

    // MARK: - Firefox

    private func scanFirefox() -> [PrivacyItem] {
        let firefox = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Firefox")
            .appendingPathComponent("Profiles")
        guard directoryExists(firefox) else { return [] }

        var items: [PrivacyItem] = []

        let profileDirs = (try? fm.contentsOfDirectory(
            at: firefox,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )) ?? []

        for profile in profileDirs {
            let places = profile.appendingPathComponent("places.sqlite")
            appendIfExists(&items, url: places,
                           name: "\(profile.lastPathComponent) 历史记录",
                           category: .firefox)

            let cookies = profile.appendingPathComponent("cookies.sqlite")
            appendIfExists(&items, url: cookies,
                           name: "\(profile.lastPathComponent) Cookie",
                           category: .firefox)

            let cache = profile.appendingPathComponent("cache2")
            appendIfExists(&items, url: cache,
                           name: "\(profile.lastPathComponent) 缓存",
                           category: .firefox)
        }

        return items
    }

    // MARK: - Quick Look

    private func scanQuickLook() -> [PrivacyItem] {
        let ql = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Caches")
            .appendingPathComponent("com.apple.QuickLook.ThumbnailsCache")
        guard directoryExists(ql) else { return [] }

        return [
            PrivacyItem(name: "Quick Look 缩略图缓存",
                        category: .quickLook,
                        url: ql,
                        estimatedSize: directorySize(ql))
        ]
    }

    // MARK: - Recent Items

    private func scanRecentItems() -> [PrivacyItem] {
        let plist = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Preferences")
            .appendingPathComponent("com.apple.recentitems.plist")
        guard fm.fileExists(atPath: plist.path) else { return [] }

        return [
            PrivacyItem(name: "最近项目记录",
                        category: .recentItems,
                        url: plist,
                        estimatedSize: fileSize(plist))
        ]
    }

    // MARK: - Download History

    private func scanDownloadHistory() -> [PrivacyItem] {
        let plist = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Preferences")
            .appendingPathComponent("com.apple.downloads.plist")
        guard fm.fileExists(atPath: plist.path) else { return [] }

        return [
            PrivacyItem(name: "下载记录",
                        category: .downloadHistory,
                        url: plist,
                        estimatedSize: fileSize(plist))
        ]
    }

    // MARK: - System Logs (> 7 days old)

    private func scanSystemLogs() -> [PrivacyItem] {
        let logsDir = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
        guard directoryExists(logsDir) else { return [] }

        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        var totalSize: Int64 = 0
        var logURLs: [URL] = []

        // Recursively enumerate `.log` files
        guard let enumerator = fm.enumerator(
            at: logsDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "log" else { continue }
            guard let values = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey]
            ) else { continue }

            if let modDate = values.contentModificationDate, modDate < sevenDaysAgo {
                logURLs.append(fileURL)
                totalSize += Int64(values.fileSize ?? 0)
            }
        }

        guard !logURLs.isEmpty else { return [] }

        // If there are many small log files we expose them as a single
        // bundle so the user isn't overwhelmed with hundreds of rows.
        return [
            PrivacyItem(name: "过期系统日志 (\(logURLs.count) 个文件)",
                        category: .systemLogs,
                        url: logsDir,
                        estimatedSize: totalSize)
        ]
    }

    // MARK: - Helpers

    /// Append a `PrivacyItem` for `url` to `items` if the path exists.
    private func appendIfExists(
        _ items: inout [PrivacyItem],
        url: URL,
        name: String,
        category: PrivacyItem.PrivacyCategory
    ) {
        guard fm.fileExists(atPath: url.path) || directoryExists(url) else { return }
        let size = directoryExists(url) ? directorySize(url) : fileSize(url)
        items.append(PrivacyItem(
            name: name,
            category: category,
            url: url,
            estimatedSize: size
        ))
    }

    private func fileSize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return 0 }
        return Int64(values.fileSize ?? 0)
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]) else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}

// MARK: - URL helpers

private extension URL {
    /// Returns the Chrome profile directories found inside this Chrome
    /// user-data directory (e.g. `Default`, `Profile 1`, …).
    func profileDirectories(fm: FileManager) -> [URL] {
        guard let contents = try? fm.contentsOfDirectory(
            at: self,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        // Chrome uses "Default" and "Profile N" for its profile directories.
        return contents.filter { url in
            let name = url.lastPathComponent
            return name == "Default" || name.hasPrefix("Profile ")
        }
    }
}
