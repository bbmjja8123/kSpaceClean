import Foundation

// MARK: - System Clean Category

/// Coarse category a deep-clean item belongs to. Maps to the three system
/// surfaces the Pro deep-clean flow manages: user launch agents, launch
/// daemons, and preference panes.
///
/// `rawValue` is deliberately alphabetical (`launchAgents` <
/// `launchDaemons` < `preferencePanes`) so ``DeepCleanViewModel/groupedItems``
/// can render the sections in a stable order without extra metadata.
internal enum SystemCleanCategory: String, CaseIterable, Sendable {
    /// `/Library/LaunchAgents` — per-user launch agents.
    case launchAgents = "launchAgents"
    /// `/Library/LaunchDaemons` — system-wide launch daemons.
    case launchDaemons = "launchDaemons"
    /// `/Library/PreferencePanes` — preference-pane bundles.
    case preferencePanes = "preferencePanes"

    /// Human-readable section header shown in ``SystemCleanGroupView``.
    var displayName: String {
        switch self {
        case .launchAgents: return "Launch Agents"
        case .launchDaemons: return "Launch Daemons"
        case .preferencePanes: return "系统偏好面板"
        }
    }

    /// SF Symbol used for the section header icon and row accent.
    var systemImage: String {
        switch self {
        case .launchAgents: return "play.circle"
        case .launchDaemons: return "play.rectangle"
        case .preferencePanes: return "slider.horizontal.3"
        }
    }
}

// MARK: - System Clean Item

/// One deletable system item surfaced by ``DeepCleanEngine/scan()``.
///
/// The model is intentionally file-centric: each item maps to exactly one
/// path on disk (`/Library/LaunchAgents/foo.plist`, `/Library/LaunchDaemons/
/// bar.plist`, or `/Library/PreferencePanes/baz.prefPane`), so cleaning is a
/// deterministic per-path delete preceded by a single batch backup.
internal struct SystemCleanItem: Identifiable, Equatable, Sendable {
    /// Identity — the absolute path of the item on disk.
    var id: String { url.path }
    /// Human-readable name: the launchd `Label` for agents/daemons, the
    /// bundle display name for preference panes.
    let displayName: String
    /// Absolute URL of the item on disk.
    let url: URL
    /// Which category the item belongs to.
    let category: SystemCleanCategory
    /// Aggregate size on disk in bytes. Recursive for `.prefPane` bundles,
    /// a single-file stat otherwise.
    let sizeBytes: Int64
    /// `true` for Apple-owned items (launchd label prefixed `com.apple.` or
    /// `com.macos.`). Such items are never deletable.
    let isProtected: Bool
    /// Bundle identifier of the app the item belongs to, when derivable
    /// from the plist's `ProgramArguments`; `nil` otherwise.
    let associatedBundleID: String?
}

// MARK: - Deep Clean Engine Protocol

/// Abstraction over ``DeepCleanEngine`` so ``DeepCleanViewModel`` can be
/// tested with an in-memory stub (see `DeepCleanViewModelTests/StubEngine`).
///
/// `Sendable` because the view-model stores the engine as a property and
/// calls it across actor boundaries; the methods are `async` so the protocol
/// never blocks the main actor.
internal protocol DeepCleanEngining: AnyObject, Sendable {
    /// Scans the three system directories and returns every detectable item.
    /// Implementations may return a partial list (per-directory degradation)
    /// or throw for catastrophic failures.
    func scan() async throws -> [SystemCleanItem]

    /// Backs up and deletes the given items. Returns the number of items
    /// actually deleted. Implementations must refuse protected items and
    /// must back up before deleting.
    func clean(_ items: [SystemCleanItem]) async throws -> Int
}

// MARK: - Deep Clean Engine

/// Scans `/Library/LaunchAgents`, `/Library/LaunchDaemons`, and
/// `/Library/PreferencePanes` for system-level items and deletes them (after
/// a full backup) for the Pro deep-clean flow.
///
/// Safety properties, mirroring `TrashMover`:
/// 1. **Backup before delete** — ``clean(_:)`` copies every selected item
///    into ``BackupManager`` first. If the backup throws, the whole
///    operation aborts and nothing is deleted.
/// 2. **Apple items are never deleted** — items whose launchd label starts
///    with `com.apple.` or `com.macos.` are flagged ``SystemCleanItem/isProtected``,
///    and both the engine's ``clean(_:)`` and the view-model's toggle guard
///    refuse them.
/// 3. **Per-directory degradation** — a directory that is unreadable (e.g. a
///    TCC denial) contributes zero items instead of failing the whole scan,
///    so the UI always renders the readable subset.
///
/// The three directory URLs are injectable so tests can point the engine at
/// temporary fixtures without touching real system directories.
internal actor DeepCleanEngine: DeepCleanEngining {

    /// Bundle identifier used for the batch backup and audit records so a
    /// deep-clean backup is distinguishable from an uninstall backup.
    static let backupBundleID = "app.kraftly.kfresh.deepclean"

    private let fileManager: FileManager
    private let backupManager: BackupManager
    private let auditLogger: AuditLogger?
    private let launchAgentsURL: URL
    private let launchDaemonsURL: URL
    private let preferencePanesURL: URL

    /// Creates an engine.
    ///
    /// - Parameters:
    ///   - fileManager: File manager used for all filesystem access.
    ///   - backupManager: Backup store; every selected item is copied here
    ///     before deletion.
    ///   - auditLogger: Optional audit logger. When `nil`, cleaning still
    ///     works but no events are recorded.
    ///   - launchAgentsURL: Directory scanned for `.plist` launch agents.
    ///     Defaults to `/Library/LaunchAgents`.
    ///   - launchDaemonsURL: Directory scanned for `.plist` launch daemons.
    ///     Defaults to `/Library/LaunchDaemons`.
    ///   - preferencePanesURL: Directory scanned for `.prefPane` bundles.
    ///     Defaults to `/Library/PreferencePanes`.
    init(
        fileManager: FileManager = .default,
        backupManager: BackupManager,
        auditLogger: AuditLogger?,
        launchAgentsURL: URL = URL(fileURLWithPath: "/Library/LaunchAgents"),
        launchDaemonsURL: URL = URL(fileURLWithPath: "/Library/LaunchDaemons"),
        preferencePanesURL: URL = URL(fileURLWithPath: "/Library/PreferencePanes")
    ) {
        self.fileManager = fileManager
        self.backupManager = backupManager
        self.auditLogger = auditLogger
        self.launchAgentsURL = launchAgentsURL
        self.launchDaemonsURL = launchDaemonsURL
        self.preferencePanesURL = preferencePanesURL
    }

    // MARK: Scan

    /// Scans all three system directories and returns the flat item list.
    ///
    /// Per-directory failures degrade to an empty contribution for that
    /// directory (never a thrown scan). This is intentional:
    /// `/Library/PreferencePanes` may be TCC-denied on one machine while
    /// `/Library/LaunchAgents` is readable, and the Pro flow should still
    /// show the readable subset.
    func scan() async throws -> [SystemCleanItem] {
        var items: [SystemCleanItem] = []
        items.append(contentsOf: scanDirectory(launchAgentsURL, category: .launchAgents))
        items.append(contentsOf: scanDirectory(launchDaemonsURL, category: .launchDaemons))
        items.append(contentsOf: scanDirectory(preferencePanesURL, category: .preferencePanes))
        return items
    }

    /// Lists one directory and maps each entry to a ``SystemCleanItem``.
    /// Returns an empty array on any read failure so a single denied
    /// directory cannot fail the whole scan.
    private func scanDirectory(_ dir: URL, category: SystemCleanCategory) -> [SystemCleanItem] {
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }
        return contents.compactMap { makeItem(for: $0, category: category) }
    }

    /// Builds a ``SystemCleanItem`` for one file in `category`.
    ///
    /// A file with the wrong extension for its directory is skipped
    /// (non-`.plist` in LaunchAgents, non-`.prefPane` in PreferencePanes).
    private func makeItem(for url: URL, category: SystemCleanCategory) -> SystemCleanItem? {
        let plist: NSDictionary
        switch category {
        case .launchAgents, .launchDaemons:
            guard url.pathExtension.lowercased() == "plist" else { return nil }
            plist = readPlist(at: url)
        case .preferencePanes:
            guard url.pathExtension.lowercased() == "prefpane" else { return nil }
            plist = readPlist(at: url.appendingPathComponent("Contents/Info.plist"))
        }

        let label = (plist["Label"] as? String) ?? url.deletingPathExtension().lastPathComponent

        let displayName: String
        let bundleID: String?
        switch category {
        case .launchAgents, .launchDaemons:
            displayName = label
            bundleID = associatedBundleID(from: plist)
        case .preferencePanes:
            displayName = bundleDisplayName(from: plist) ?? label
            bundleID = plist["CFBundleIdentifier"] as? String
        }

        return SystemCleanItem(
            displayName: displayName,
            url: url,
            category: category,
            sizeBytes: sizeOfItem(at: url),
            isProtected: isAppleOwned(label),
            associatedBundleID: bundleID
        )
    }

    // MARK: Clean

    /// Backs up and deletes the given items.
    ///
    /// The supplied list is expected to be the user's selection; this method
    /// defensively filters out any `isProtected` item so a UI bug can never
    /// forward an Apple-owned path to the delete loop.
    ///
    /// Order of operations:
    /// 1. Filter protected items (skipped silently, not counted).
    /// 2. Batch-backup the survivors into ``BackupManager`` under
    ///    ``backupBundleID``. If the backup throws, the operation aborts and
    ///    **nothing** is deleted — a user-visible failure is always safer
    ///    than a backup-less delete.
    /// 3. Delete each item. Per-item failures are collected and the loop
    ///    continues, so one bad path does not block the rest.
    /// 4. Audit every delete attempt in an explicit `do`/`catch` — a failing
    ///    audit log never blocks the clean.
    ///
    /// - Returns: The number of items actually deleted.
    func clean(_ items: [SystemCleanItem]) async throws -> Int {
        let deletable = items.filter { !$0.isProtected }
        guard !deletable.isEmpty else { return 0 }

        let residues = deletable.map { item in
            ResidueFile(
                url: item.url,
                type: residueType(for: item.category),
                sizeBytes: item.sizeBytes,
                confidence: 1.0,
                description: item.displayName,
                isSystemLevel: true,
                isProtected: item.isProtected
            )
        }

        do {
            _ = try await backupManager.backup(
                residues: residues,
                bundleID: Self.backupBundleID
            )
        } catch {
            await logEvent(
                action: "deepclean-backup",
                bundleID: Self.backupBundleID,
                paths: deletable.map(\.url.path),
                status: "failure",
                error: "\(error)"
            )
            throw error
        }

        var deletedCount = 0
        for item in deletable {
            let bundleID = item.associatedBundleID ?? Self.backupBundleID
            do {
                try fileManager.removeItem(at: item.url)
                deletedCount += 1
                await logEvent(
                    action: "deepclean",
                    bundleID: bundleID,
                    paths: [item.url.path],
                    status: "success",
                    error: nil
                )
            } catch {
                await logEvent(
                    action: "deepclean",
                    bundleID: bundleID,
                    paths: [item.url.path],
                    status: "failure",
                    error: "\(error)"
                )
            }
        }
        return deletedCount
    }

    // MARK: Helpers

    /// Maps a category to the `ResidueType` used for backup manifests.
    private func residueType(for category: SystemCleanCategory) -> ResidueType {
        switch category {
        case .launchAgents: return .launchAgent
        case .launchDaemons: return .launchDaemon
        case .preferencePanes: return .prefPane
        }
    }

    /// Reads a property list as an `NSDictionary`. Missing or malformed
    /// files yield an empty dictionary so downstream lookups (`Label`,
    /// `ProgramArguments`) degrade to their fallbacks instead of crashing.
    private func readPlist(at url: URL) -> NSDictionary {
        do {
            return try NSDictionary(contentsOf: url) ?? [:]
        } catch {
            return [:]
        }
    }

    /// Derives the owning app's bundle identifier from a launchd plist's
    /// `ProgramArguments`: finds the first argument ending in `.app` and
    /// reads its `CFBundleIdentifier`. Returns `nil` when no app path is
    /// present or the app's Info.plist is unreadable.
    private func associatedBundleID(from plist: NSDictionary) -> String? {
        guard let args = plist["ProgramArguments"] as? [String],
              let appPath = args.first(where: { $0.hasSuffix(".app") }) else {
            return nil
        }
        let infoURL = URL(fileURLWithPath: appPath)
            .appendingPathComponent("Contents/Info.plist")
        return readPlist(at: infoURL)["CFBundleIdentifier"] as? String
    }

    /// Returns the display name of a preference pane from its bundle
    /// Info.plist (`CFBundleDisplayName` first, then `CFBundleName`), or
    /// `nil` when neither key exists.
    private func bundleDisplayName(from plist: NSDictionary) -> String? {
        if let display = plist["CFBundleDisplayName"] as? String, !display.isEmpty {
            return display
        }
        return plist["CFBundleName"] as? String
    }

    /// Apple-owned detection. `com.apple.*` and `com.macos.*` launchd labels
    /// are system components that a user-space cleaner must never touch.
    private func isAppleOwned(_ label: String) -> Bool {
        label.hasPrefix("com.apple.") || label.hasPrefix("com.macos.")
    }

    /// Aggregate on-disk size of an item. Files are stat'd directly;
    /// directories (`.prefPane` bundles) are walked recursively.
    private func sizeOfItem(at url: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            do {
                let attrs = try fileManager.attributesOfItem(atPath: url.path)
                if let size = attrs[.size] as? NSNumber {
                    return size.int64Value
                }
            } catch {
                return 0
            }
            return 0
        }
        var total: Int64 = 0
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        for case let child as URL in enumerator {
            do {
                let values = try child.resourceValues(forKeys: [.fileSizeKey])
                if let size = values.fileSize {
                    total += Int64(size)
                }
            } catch {
                // An unreadable child does not abort the size walk.
            }
        }
        return total
    }

    /// Best-effort audit write. When no ``AuditLogger`` is configured the
    /// call is a no-op. When one is configured, write failures are swallowed
    /// so a failing audit log never blocks the clean. Uses an explicit
    /// `do`/`catch` (never `try?`) so the failure path is observable and
    /// documented here rather than silently hidden by the operator.
    private func logEvent(action: String, bundleID: String, paths: [String], status: String, error: String?) async {
        guard let logger = auditLogger else { return }
        let event = AuditEvent(
            timestamp: Date(),
            action: action,
            bundleID: bundleID,
            paths: paths,
            status: status,
            errorMessage: error
        )
        do {
            try await logger.log(event)
        } catch {
            print("DeepCleanEngine.logEvent: audit write failed for \(action): \(error)")
        }
    }
}
