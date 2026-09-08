import Foundation

/// Persists the security-scoped home-folder bookmark.
///
/// Stored in `UserDefaults` (app-scope bookmarks are small, and the
/// `files.bookmarks.app-scope` entitlement is already granted). A `createdAt`
/// timestamp accompanies the blob so diagnostics can tell "stale bookmark"
/// from "never granted".
public struct BookmarkStore: Sendable {

    public static let bookmarkKey = "kwise.powerscope.homeBookmark.v1"
    public static let createdAtKey = "kwise.powerscope.homeBookmark.createdAt"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func save(bookmark: Data, createdAt: Date = Date()) {
        defaults.set(bookmark, forKey: Self.bookmarkKey)
        defaults.set(createdAt.timeIntervalSince1970, forKey: Self.createdAtKey)
    }

    public func load() -> Data? {
        defaults.data(forKey: Self.bookmarkKey)
    }

    public var createdAt: Date? {
        let interval = defaults.double(forKey: Self.createdAtKey)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.bookmarkKey)
        defaults.removeObject(forKey: Self.createdAtKey)
    }
}

/// Errors surfaced by bookmark (de)serialization.
public enum BookmarkStoreError: Error, Equatable {
    /// The stored blob no longer resolves (app moved, home renamed, keychain
    /// rotation). The bookmark has been cleared; the UI should re-prompt.
    case stale
    /// Security-scoped access could not be started on the resolved URL.
    case accessDenied
}
