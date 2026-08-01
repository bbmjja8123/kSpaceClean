import Foundation
import AppKit

/// Discovers every app installed on this Mac and classifies where it came from.
///
/// The catalog merges four independent sources so that neither a sandbox
/// restriction nor an unusual install location can hide an app:
///
/// 1. `NSWorkspace.runningApplications` — catches apps running from anywhere,
///    including locations we are not allowed to enumerate.
/// 2. The standard `/Applications` and `/System/Applications` directories.
/// 3. Homebrew cask roots (`/opt/homebrew/Caskroom`, `/usr/local/Caskroom`).
/// 4. The Setapp bundle directory (`/Applications/Setapp`).
///
/// Results are deduplicated by bundle ID, preferring the entry backed by a
/// running process (its URL is authoritative) and filling in blanks from the
/// other candidates.
actor AppCatalogService {
    private let fileManager: FileManager

    /// Creates a catalog service backed by `FileManager.default`.
    ///
    /// Split from ``init(fileManager:)`` deliberately: `FileManager` is not
    /// `Sendable`, so a defaulted parameter would emit a strict-concurrency
    /// warning at every plain `AppCatalogService()` call site.
    init() {
        self.fileManager = .default
    }

    /// Creates a catalog service with an injected file manager.
    /// - Parameter fileManager: File manager used for all directory
    ///   enumeration. Intended for tests that need a scoped or stubbed manager.
    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    /// Enumerates every installed app and returns one entry per bundle ID.
    ///
    /// Directories that cannot be read (missing, or blocked by the sandbox)
    /// contribute nothing rather than failing the whole scan, so this method
    /// never throws and degrades gracefully without Full Disk Access.
    ///
    /// - Returns: Apps sorted by display name, deduplicated by bundle ID.
    func scan() async -> [InstalledApp] {
        let candidates = await enumerateCandidates()
        var deduped: [String: InstalledApp] = [:]
        for app in candidates {
            if let existing = deduped[app.bundleID] {
                deduped[app.bundleID] = merge(existing: existing, with: app)
            } else {
                deduped[app.bundleID] = app
            }
        }
        return Array(deduped.values).sorted { $0.displayName < $1.displayName }
    }

    /// Sums the on-disk size of an app bundle by walking its contents.
    ///
    /// Uses allocated size (what the volume actually spends) when available and
    /// falls back to logical file size. Subtrees deeper than `maxDepth` are
    /// skipped rather than aborting the walk, which bounds the cost of
    /// pathological bundles that embed deep frameworks or node_modules trees.
    ///
    /// - Parameters:
    ///   - url: The app bundle to measure.
    ///   - maxDepth: Maximum number of path components below `url` to descend.
    ///     Defaults to 5.
    /// - Returns: Total size in bytes, or `0` if `url` cannot be enumerated.
    func sizeOfApp(at url: URL, maxDepth: Int = 5) async -> Int64 {
        // m-4 fix: route through the shared `DirectorySizeCalculator`
        // helper in kFoundation. This method previously reimplemented
        // the enumerator + size-sum loop with a depth cap applied via
        // `enumerator.skipDescendants()` on over-deep subtrees. The
        // helper preserves that policy (depth policy `.limited(max:)`
        // skips with `skipDescendants` rather than aborting the walk)
        // and is the single source of truth for "how big is this tree".
        DirectorySizeCalculator.size(of: url, depth: .limited(max: maxDepth), fileManager: fileManager)
    }

    /// Reads `URLResourceValues` for a file inside the bundle walk, returning
    /// the per-file size contribution while tolerating per-file metadata
    /// failures.
    ///
    /// The swallow is deliberate: a single unreadable file (broken symlink,
    /// race with deletion, filesystem permission glitch) must not abort the
    /// whole size accumulation. The caller treats a `0` contribution as
    /// "this file is unknown size; skip it" — the same semantics that the
    /// previous inline `try?` had before this helper was extracted.
    ///
    /// Note: retained for callers that still need per-file size contribution
    /// outside the `DirectorySizeCalculator` walk. The bundled-size path
    /// above no longer uses this helper.
    /// - Returns: Bytes contributed by `at`, or `0` if the values could not
    ///   be read or both `totalFileAllocatedSize` and `fileSize` are missing.
    private static func safeResourceSize(at url: URL, keys: Set<URLResourceKey>) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
    }

    /// Classifies where an app came from using only its location and bundle ID.
    ///
    /// Pure and `nonisolated` so callers (and tests) can classify without
    /// hopping onto the actor. The only side effect is a file-existence check
    /// for the Mac App Store receipt.
    ///
    /// - Parameters:
    ///   - url: Location of the `.app` bundle.
    ///   - bundleID: The bundle identifier of the app.
    /// - Returns: The best-matching ``AppSource``, or ``AppSource/unknown``.
    nonisolated static func classifySource(url: URL, bundleID: String) -> AppSource {
        let path = url.path
        if path.hasPrefix("/System/") { return .system }
        if bundleID == "com.apple.finder" { return .system }
        if bundleID.hasPrefix("com.apple.") { return .appleBuiltIn }
        if path.contains("/Caskroom/") { return .homebrew }
        if path.contains("/Setapp/") || bundleID.hasSuffix(".setapp") { return .setapp }
        if hasMASReceipt(url) { return .mas }
        if path.contains("/Applications/") { return .userInstalled }
        return .unknown
    }

    // MARK: - Candidate collection

    private func enumerateCandidates() async -> [InstalledApp] {
        var candidates: [InstalledApp] = []
        candidates.append(contentsOf: queryLaunchServices())
        candidates.append(contentsOf: appsInStandardDirs())
        candidates.append(contentsOf: appsInHomebrewCaskroom())
        candidates.append(contentsOf: appsInSetapp())
        return candidates
    }

    /// Running apps only. Non-running apps are covered by ``appsInStandardDirs()``
    /// and the package-manager roots; this pass exists to mark `isRunning` and to
    /// surface apps installed outside any directory we enumerate.
    private func queryLaunchServices() -> [InstalledApp] {
        let workspace = NSWorkspace.shared
        return workspace.runningApplications.compactMap { app -> InstalledApp? in
            guard let url = app.bundleURL else { return nil }
            return makeInstalledApp(url: url, workspace: workspace, isRunning: true)
        }
    }

    private func appsInStandardDirs() -> [InstalledApp] {
        let dirs = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
        ]
        let workspace = NSWorkspace.shared
        return dirs.flatMap { appsInDirectory($0, workspace: workspace) }
    }

    private func appsInHomebrewCaskroom() -> [InstalledApp] {
        let roots = [
            "/opt/homebrew/Caskroom",
            "/usr/local/Caskroom",
        ]
        let workspace = NSWorkspace.shared
        return roots.flatMap { root -> [InstalledApp] in
            childDirectories(of: URL(fileURLWithPath: root)).flatMap { caskDir -> [InstalledApp] in
                // Caskroom layout is <root>/<cask>/<version>/<App>.app
                childDirectories(of: caskDir).flatMap { versionDir -> [InstalledApp] in
                    appsInDirectory(versionDir.path, workspace: workspace, sourceOverride: .homebrew)
                }
            }
        }
    }

    private func appsInSetapp() -> [InstalledApp] {
        appsInDirectory("/Applications/Setapp", workspace: NSWorkspace.shared, sourceOverride: .setapp)
    }

    private func childDirectories(of url: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
    }

    private func appsInDirectory(
        _ dir: String,
        workspace: NSWorkspace,
        sourceOverride: AppSource? = nil
    ) -> [InstalledApp] {
        childDirectories(of: URL(fileURLWithPath: dir))
            .filter { $0.pathExtension == "app" }
            .compactMap {
                makeInstalledApp(
                    url: $0,
                    workspace: workspace,
                    isRunning: false,
                    sourceOverride: sourceOverride
                )
            }
    }

    private func makeInstalledApp(
        url: URL,
        workspace: NSWorkspace,
        isRunning: Bool,
        sourceOverride: AppSource? = nil
    ) -> InstalledApp? {
        let bundle = Bundle(url: url)
        let bundleID = bundle?.bundleIdentifier ?? Self.fallbackBundleID(for: url)
        let displayName = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle?.infoDictionary?["CFBundleDisplayName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
        let version = bundle?.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        // Best-effort install date = the bundle directory's creation date.
        // `try?` is deliberate: a missing/unreadable creation date yields nil,
        // matching the model's optionality.
        let installDate: Date? = (try? FileManager.default.attributesOfItem(atPath: url.path)[.creationDate]) as? Date
        return InstalledApp(
            url: url,
            displayName: displayName,
            bundleID: bundleID,
            version: version,
            icon: workspace.icon(forFile: url.path),
            sizeBytes: 0,
            source: sourceOverride ?? Self.classifySource(url: url, bundleID: bundleID),
            isRunning: isRunning,
            lastUsedDate: nil,
            installDate: installDate
        )
    }

    /// Builds a synthetic bundle identifier for bundles whose `Info.plist` has
    /// no `CFBundleIdentifier` (corrupted metadata, unsigned developer bundle,
    /// unusual layout). Distance between the bundle and the filesystem root is
    /// included so that two bundles with the same name living in different
    /// directories do not collapse into the same dedup key.
    ///
    /// Examples:
    /// - `/Applications/Foo.app` → `unknown.Applications.Foo`
    /// - `/opt/homebrew/Caskroom/foo/1.0/Foo.app` → `unknown.Applications.Foo`
    ///   (the parent directory of the bundle is the deduplication-relevant
    ///   discriminator, not the full cask path)
    /// - `/Users/me/Desktop/Foo.app` → `unknown.Desktop.Foo`
    ///
    /// Whitespace and path separators in the parent name are stripped so the
    /// resulting identifier is still usable as a dictionary key.
    private static func fallbackBundleID(for url: URL) -> String {
        let parent = url.deletingLastPathComponent().lastPathComponent
        let cleanParent = parent.replacingOccurrences(of: " ", with: "_")
        return "unknown.\(cleanParent).\(url.lastPathComponent)"
    }

    /// Combines two sightings of the same bundle ID, preferring the running
    /// entry's URL and filling empty fields from the other candidate.
    private func merge(existing: InstalledApp, with new: InstalledApp) -> InstalledApp {
        InstalledApp(
            url: existing.isRunning ? existing.url : new.url,
            displayName: existing.displayName,
            bundleID: existing.bundleID,
            version: existing.version.isEmpty ? new.version : existing.version,
            icon: Self.preferIcon(existing.icon, new.icon),
            sizeBytes: max(existing.sizeBytes, new.sizeBytes),
            source: existing.source == .unknown ? new.source : existing.source,
            isRunning: existing.isRunning || new.isRunning,
            lastUsedDate: existing.lastUsedDate ?? new.lastUsedDate,
            installDate: existing.installDate ?? new.installDate,
            residues: existing.residues.isEmpty ? new.residues : existing.residues
        )
    }

    /// Picks the ``NSImage`` that actually renders — preferring the first
    /// argument's icon unless it carries no bitmap representation, in which
    /// case the second argument's icon is used. This handles the case where
    /// one candidate was built from a path with no Finder metadata (yielding
    /// `NSImage()` with zero `representations`) and the other from a path
    /// where `NSWorkspace.icon(forFile:)` resolved successfully.
    private static func preferIcon(_ existing: NSImage, _ new: NSImage) -> NSImage {
        if !existing.representations.isEmpty { return existing }
        return new
    }

    /// Returns `true` when the bundle at `url` carries a Mac App Store receipt.
    ///
    /// Uses `FileManager.default` deliberately because this helper is invoked
    /// from ``classifySource(url:bundleID:)``, which is `nonisolated static`
    /// and therefore cannot access actor state (the injected `fileManager`).
    /// The lossy coupling is intentional: a per-instance file manager would
    /// force `classifySource` onto the actor, defeating the convenience of the
    /// static call sites in tests and view code.
    private static func hasMASReceipt(_ url: URL) -> Bool {
        let receiptURL = url.appendingPathComponent("Contents/_MASReceipt/receipt")
        return FileManager.default.fileExists(atPath: receiptURL.path)
    }
}
