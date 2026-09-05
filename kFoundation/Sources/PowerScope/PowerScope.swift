import Foundation

/// Coarse access level kWise currently holds over the filesystem.
///
/// MAS sandboxing means Full Disk Access is unobtainable; the power model is
/// instead "container-only by default, home folder granted via a
/// user-driven security-scoped bookmark" (see ``PowerScope``).
public enum ScopeLevel: Int, Sendable, Comparable {
    /// App container + whatever public directories the OS lets a sandboxed
    /// app read (probed at runtime, never assumed).
    case containerOnly = 0
    /// The user granted the home folder via NSOpenPanel; a security-scoped
    /// bookmark is persisted and resolvable.
    case homeGranted = 1

    public static func < (lhs: ScopeLevel, rhs: ScopeLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What kWise may read right now, as observed at runtime.
public struct ScopeCapability: Sendable, Equatable {
    public let level: ScopeLevel
    /// Resolved target of the persisted home-folder bookmark, if any.
    public let grantedRoot: URL?
    /// Public directories the probe confirmed readable this session.
    public let readablePublicDirs: Set<String>

    public init(level: ScopeLevel,
                grantedRoot: URL? = nil,
                readablePublicDirs: Set<String> = []) {
        self.level = level
        self.grantedRoot = grantedRoot
        self.readablePublicDirs = readablePublicDirs
    }

    /// Whether `url` is inside the granted root (or readable via a probed
    /// public dir's prefix).
    public func canRead(_ url: URL) -> Bool {
        switch level {
        case .homeGranted:
            guard let root = grantedRoot else { return false }
            return url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path)
        case .containerOnly:
            // Public-dir prefixes are probed paths like "~/Library/Caches".
            return readablePublicDirs.contains { prefix in
                url.standardizedFileURL.path.hasPrefix(
                    NSString(string: prefix).expandingTildeInPath
                )
            }
        }
    }
}

/// Abstraction every scanner consults instead of assuming what the sandbox
/// allows. Conforms so `PowerScope` can be swapped for a stub in tests.
public protocol PowerScopeProviding: Sendable {
    /// Current capability snapshot (bookmark resolved + dirs probed).
    func capability() async -> ScopeCapability
    /// Present NSOpenPanel, persist a security-scoped bookmark for the
    /// chosen folder, and return the refreshed capability.
    func grantHomeFolder() async throws -> ScopeCapability
    /// Drop the persisted bookmark and fall back to `.containerOnly`.
    func revoke() async
    /// Run `body` with the security scope of `url` active (no-op when the
    /// level already covers it).
    func withAccess<T: Sendable>(_ url: URL, _ body: (URL) async throws -> T) async throws -> T
}
