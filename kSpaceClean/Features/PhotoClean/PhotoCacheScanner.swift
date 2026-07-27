import Foundation

/// Represents a single photo-cache item discovered by the scanner.
public struct PhotoCacheItem: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let category: PhotoCacheCategory
    public let url: URL
    public let estimatedSize: Int64
    public var isSelected: Bool = true

    public enum PhotoCacheCategory: String, Sendable, CaseIterable {
        case photosApp = "Photos App"
        case iPhoto = "iPhoto"
        case iOSBackup = "iOS 备份"
        case photoStream = "照片流"

        public var icon: String {
            switch self {
            case .photosApp:   return "photo.on.rectangle"
            case .iPhoto:      return "photo.stack"
            case .iOSBackup:   return "iphone.gen2"
            case .photoStream: return "icloud"
            }
        }
    }
}

/// Scans the system for known photo-library caches, old iPhoto data,
/// abandoned iOS backups, and photo-stream temporary files.
///
/// All scan paths are derived from the user's home directory and are
/// inherently sandbox-compatible when Full Disk Access is granted.
public final class PhotoCacheScanner: Sendable {
    private let fm = FileManager.default
    private let home: URL

    public init() {
        home = FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Public API

    /// Synchronously enumerates known photo-cache locations and returns
    /// an array of `PhotoCacheItem` for each directory that exists.
    public func scan() -> [PhotoCacheItem] {
        var items: [PhotoCacheItem] = []

        // 1. Photos.app cache (~/Library/Containers/com.apple.Photos/...)
        if let item = scanPhotosAppCache() {
            items.append(item)
        }

        // 2. iPhoto library cache (~/Pictures/iPhoto Library/)
        if let item = scaniPhotoLibrary() {
            items.append(item)
        }

        // 3. iOS backups (~/Library/Application Support/MobileSync/Backup/)
        let backupItems = scaniOSBackups()
        items.append(contentsOf: backupItems)

        // 4. Photo Stream cache (~/Library/Caches/com.apple.Photos/)
        if let item = scanPhotoStreamCache() {
            items.append(item)
        }

        return items
    }

    /// Moves every item in `items` to the Trash.
    ///
    /// - Returns: The number of items that were successfully trashed.
    public func cleanup(items: [PhotoCacheItem]) async -> Int {
        var successCount = 0

        for item in items {
            guard fm.fileExists(atPath: item.url.path) else { continue }
            do {
                var trashedURL: NSURL?
                try fm.trashItem(at: item.url, resultingItemURL: &trashedURL)
                successCount += 1
            } catch {
                // Silently skip individual failures so one permission
                // issue does not block the entire cleanup pass.
                continue
            }
        }

        return successCount
    }

    // MARK: - Scan Helpers

    private func scanPhotosAppCache() -> PhotoCacheItem? {
        let cacheDir = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Containers")
            .appendingPathComponent("com.apple.Photos")
            .appendingPathComponent("Data")
            .appendingPathComponent("Library")
            .appendingPathComponent("Caches")

        return itemIfExists(at: cacheDir, category: .photosApp)
    }

    private func scaniPhotoLibrary() -> PhotoCacheItem? {
        let iPhotoDir = home
            .appendingPathComponent("Pictures")
            .appendingPathComponent("iPhoto Library")

        // iPhoto can be a bundle (directory) or absent on modern macOS.
        // We only report it when the directory actually exists and has
        // the expected sub-structure (Thumbnails/ or .apdisk).
        guard fm.fileExists(atPath: iPhotoDir.path),
              let enumerator = fm.enumerator(
                at: iPhotoDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else { return nil }

        var totalSize: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]),
                  let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize
            else { continue }
            totalSize += Int64(allocated)
        }

        guard totalSize > 0 else { return nil }

        return PhotoCacheItem(
            name: "iPhoto 图库缓存",
            category: .iPhoto,
            url: iPhotoDir,
            estimatedSize: totalSize
        )
    }

    private func scaniOSBackups() -> [PhotoCacheItem] {
        let backupDir = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("MobileSync")
            .appendingPathComponent("Backup")

        guard fm.fileExists(atPath: backupDir.path) else { return [] }

        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: backupDir,
                includingPropertiesForKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        var items: [PhotoCacheItem] = []
        for url in contents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let size = directorySize(url)
            // Only report non-trivial backups (>= 1 MB).
            guard size >= 1_048_576 else { continue }

            let deviceName = url.lastPathComponent
            items.append(PhotoCacheItem(
                name: String(format: "iOS 备份 — %@", deviceName),
                category: .iOSBackup,
                url: url,
                estimatedSize: size
            ))
        }

        return items
    }

    private func scanPhotoStreamCache() -> PhotoCacheItem? {
        let cacheDir = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Caches")
            .appendingPathComponent("com.apple.Photos")

        return itemIfExists(at: cacheDir, category: .photoStream)
    }

    // MARK: - Utilities

    /// Calculates the total allocated size of a directory (recursive).
    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        var total: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]),
                  let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize
            else { continue }
            total += Int64(allocated)
        }
        return total
    }

    /// Returns a `PhotoCacheItem` if the directory exists and has content.
    private func itemIfExists(at url: URL, category: PhotoCacheItem.PhotoCacheCategory) -> PhotoCacheItem? {
        guard fm.fileExists(atPath: url.path) else { return nil }
        let size = directorySize(url)
        guard size > 0 else { return nil }

        return PhotoCacheItem(
            name: category.rawValue,
            category: category,
            url: url,
            estimatedSize: size
        )
    }
}
