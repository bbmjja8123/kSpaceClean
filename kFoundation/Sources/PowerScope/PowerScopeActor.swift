import AppKit
import Foundation

/// The concrete ``PowerScopeProviding`` implementation.
///
/// Lifecycle:
/// 1. On init, any persisted bookmark is resolved. Resolution failure
///    deletes the blob (`.stale`) and the level degrades to
///    ``ScopeLevel/containerOnly`` — the UI re-prompts as a first-class
///    flow, not an error toast.
/// 2. `grantHomeFolder()` presents NSOpenPanel (main actor), starts
///    security-scoped access, persists a `.withSecurityScope` bookmark,
///    and re-probes.
/// 3. Public-dir readability is probed per session; scanners consult
///    ``ScopeCapability`` instead of assuming sandbox behavior.
public actor PowerScope: PowerScopeProviding {

    private let bookmarks: BookmarkStore
    private let probe: ScopeProbe
    private var cachedCapability: ScopeCapability

    public init(bookmarks: BookmarkStore = BookmarkStore(), probe: ScopeProbe = ScopeProbe()) {
        self.bookmarks = bookmarks
        self.probe = probe
        self.cachedCapability = ScopeCapability(level: .containerOnly)
    }

    /// Resolve any persisted bookmark and probe public dirs. Call once per
    /// app session (cheap); callers may re-invoke after `revoke()`.
    public func refresh() async -> ScopeCapability {
        let readable = probe.readablePublicDirs()
        if let blob = bookmarks.load() {
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: blob,
                                  options: .withSecurityScope,
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale)
                if stale {
                    // Re-persist a fresh bookmark so the next launch resolves.
                    if let fresh = try? url.bookmarkData(options: .withSecurityScope) {
                        bookmarks.save(bookmark: fresh)
                    }
                }
                cachedCapability = ScopeCapability(level: .homeGranted,
                                                   grantedRoot: url,
                                                   readablePublicDirs: readable)
                return cachedCapability
            } catch {
                // Stale beyond repair — clear and fall back honestly.
                bookmarks.clear()
            }
        }
        cachedCapability = ScopeCapability(level: .containerOnly,
                                           grantedRoot: nil,
                                           readablePublicDirs: readable)
        return cachedCapability
    }

    public func capability() async -> ScopeCapability {
        cachedCapability
    }

    /// Present the home-folder grant panel. Must eventually run on the main
    /// actor (NSOpenPanel); the await bridges isolation.
    @MainActor
    private func presentPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.message = "kWise needs access to your home folder to scan caches, logs and app leftovers."
        panel.prompt = "Grant Access"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    public func grantHomeFolder() async throws -> ScopeCapability {
        guard let url = await presentPanel() else {
            throw BookmarkStoreError.accessDenied
        }
        let gained = url.startAccessingSecurityScopedResource()
        defer { if gained { url.stopAccessingSecurityScopedResource() } }
        let blob = try url.bookmarkData(options: .withSecurityScope)
        bookmarks.save(bookmark: blob)
        return await refresh()
    }

    public func revoke() async {
        bookmarks.clear()
        _ = await refresh()
    }

    public func withAccess<T: Sendable>(_ url: URL,
                                        _ body: (URL) async throws -> T) async throws -> T {
        if cachedCapability.canRead(url) {
            return try await body(url)
        }
        let gained = url.startAccessingSecurityScopedResource()
        defer { if gained { url.stopAccessingSecurityScopedResource() } }
        guard gained || cachedCapability.level == .homeGranted else {
            throw BookmarkStoreError.accessDenied
        }
        return try await body(url)
    }
}
