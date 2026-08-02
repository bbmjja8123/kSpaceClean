import Foundation

/// Actor that enumerates and mutates macOS startup items visible to the
/// app — login items, launch agents, launch daemons, and pref panes (the
/// latter two surface only when they have a corresponding plist on disk).
///
/// ## Scope
///
/// - User LaunchAgents: `~/Library/LaunchAgents`
/// - System LaunchAgents: `/Library/LaunchAgents` (protected — toggle /
///   remove are refused with ``StartupError/protected``)
/// - System LaunchDaemons: `/Library/LaunchDaemons` (protected)
/// - PrefPanes: `~/Library/PreferencePanes` and `/Library/PreferencePanes`
///
/// ## Concurrency
///
/// All public methods are `async` because they perform file I/O and
/// potentially long-running plist parsing. `setEnabled` and `remove`
/// mutate on-disk state, so callers from the UI must trap errors
/// (`StartupError.protected`, `.writeFailed`).
///
/// ## Errors
///
/// - ``StartupError/protected`` — caller asked to mutate a system-owned
///   launch item.
/// - ``StartupError/writeFailed`` — the underlying plist write failed.
/// - ``StartupError/notFound`` — the file backing the item no longer exists.
enum StartupError: Error, LocalizedError {
    case protected
    case writeFailed
    case notFound

    var errorDescription: String? {
        switch self {
        case .protected:
            return "系统级启动项受保护，无法修改"
        case .writeFailed:
            return "写入 plist 失败"
        case .notFound:
            return "找不到对应的 plist 文件"
        }
    }
}

/// Protocol abstraction over ``StartupItemManager`` so the view-model
/// (`StartupItemsViewModel`) can be exercised against an in-memory stub
/// during tests without touching the real `~/Library/LaunchAgents` paths.
///
/// All members are `async` because the real implementation is an actor
/// that does file I/O. Conforming types can be actors or classes — the
/// view-model only ever calls them through `await`.
protocol StartupItemManaging: AnyObject, Sendable {
    /// Enumerate startup items visible to the app, scoped to user-level
    /// launch agents and accessible (read-only) system paths.
    func listItems() async throws -> [StartupItem]

    /// Toggle the launch item's enabled state by writing/clearing the
    /// `Disabled` key in its plist. Throws `StartupError.protected`
    /// for system-level items.
    func setEnabled(_ enabled: Bool, for item: StartupItem) async throws

    /// Move the launch item's plist into the application's startup-item
    /// backup folder. Original path becomes empty so the UI reload shows
    /// the row removed.
    func remove(_ item: StartupItem) async throws
}

/// Concrete ``StartupItemManaging`` backed by `FileManager`. Default
/// initializer uses `.default` so callers can inject a custom manager
/// for testing.
///
/// `actor` isolation serializes all filesystem access — SwiftUI drivers
/// can `await` these methods safely without explicit locking.
actor StartupItemManager: StartupItemManaging {
    private let fileManager: FileManager

    /// Creates the manager with the default `FileManager`.
    ///
    /// `FileManager` is non-Sendable, so a defaulted parameter would emit
    /// strict-concurrency warnings at every plain `StartupItemManager()` call
    /// site; the explicit-injection init below exists for tests.
    init() {
        self.fileManager = .default
    }

    /// Creates the manager with an explicit file manager (tests only).
    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    // MARK: - listItems

    /// Enumerate the standard LaunchAgents, LaunchDaemons, and PrefPane
    /// directories. Each plist is parsed into a ``StartupItem``; items
    /// from system directories are flagged `isProtected = true` so the
    /// UI can disable their toggle / remove controls.
    func listItems() async throws -> [StartupItem] {
        var items: [StartupItem] = []

        // User launch agents — mutable, per-user.
        let userAgents = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/LaunchAgents")
        items.append(contentsOf: scanItems(in: userAgents, type: .launchAgent, system: false))

        // System launch agents — read-only via TCC + we mark protected.
        let systemAgents = URL(fileURLWithPath: "/Library/LaunchAgents")
        items.append(contentsOf: scanItems(in: systemAgents, type: .launchAgent, system: true))

        // System launch daemons — always protected (root-owned processes).
        let systemDaemons = URL(fileURLWithPath: "/Library/LaunchDaemons")
        items.append(contentsOf: scanItems(in: systemDaemons, type: .launchDaemon, system: true))

        // PrefPanes — both user and system trees, system marked protected.
        let userPrefPanes = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/PreferencePanes")
        items.append(contentsOf: scanItems(in: userPrefPanes, type: .prefPane, system: false))

        let systemPrefPanes = URL(fileURLWithPath: "/Library/PreferencePanes")
        items.append(contentsOf: scanItems(in: systemPrefPanes, type: .prefPane, system: true))

        return items.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // MARK: - Mutate

    /// Write (or remove) the `Disabled` key inside the item's plist to
    /// toggle whether `launchd` loads it on next boot / login.
    ///
    /// System-level items (`isProtected = true`) are refused with
    /// ``StartupError/protected`` before any I/O is attempted.
    func setEnabled(_ enabled: Bool, for item: StartupItem) async throws {
        guard !item.isProtected else { throw StartupError.protected }
        guard fileManager.fileExists(atPath: item.url.path) else { throw StartupError.notFound }

        var dict = readPlist(at: item.url)
        if enabled {
            dict.removeValue(forKey: "Disabled")
        } else {
            dict["Disabled"] = true
        }
        let nsDict = dict as NSDictionary
        guard nsDict.write(to: item.url, atomically: true) else {
            throw StartupError.writeFailed
        }
    }

    /// Move the launch item's plist into `~/Library/Application Support/
    /// app.kraftly.kfresh/Backups/StartupItems/`. We do NOT modify the
    /// file content — callers trust the backup location to be a full
    /// reversible copy.
    func remove(_ item: StartupItem) async throws {
        guard !item.isProtected else { throw StartupError.protected }
        guard fileManager.fileExists(atPath: item.url.path) else { throw StartupError.notFound }

        let backupRoot = backupDirectory()
        do {
            try fileManager.createDirectory(
                at: backupRoot,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            // Directory already existing is fine (createDirectory returns
            // an error if the directory exists at the path), but any
            // permission issue we surface.
            if !fileManager.fileExists(atPath: backupRoot.path) {
                throw StartupError.writeFailed
            }
        }
        let dest = backupRoot.appendingPathComponent(item.url.lastPathComponent)
        do {
            try fileManager.moveItem(at: item.url, to: dest)
        } catch {
            throw StartupError.writeFailed
        }
    }

    // MARK: - Internal helpers

    /// Lists the `.plist` files inside `directory`, parsing each into a
    /// ``StartupItem``. If the directory itself is missing or unreadable
    /// (sandbox denial, missing path), the call returns an empty array
    /// instead of throwing — startup-item enumeration should never
    /// cascade a hard error up to the UI.
    private func scanItems(in directory: URL, type: StartupItemType, system: Bool) -> [StartupItem] {
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            return []
        }
        return contents
            .filter { $0.pathExtension == "plist" }
            .map { parseLaunchItem(at: $0, type: type, system: system) }
    }

    /// Best-effort plist read — returns an empty dictionary on any error
    /// so a corrupted plist is reported as an enabled, nameless item
    /// rather than crashing the scan.
    private func readPlist(at url: URL) -> [String: Any] {
        do {
            let ns = try NSDictionary(contentsOf: url)
            return (ns as? [String: Any]) ?? [:]
        } catch {
            return [:]
        }
    }

    /// Parses a single plist into a ``StartupItem``. We surface the
    /// `Label` for `name` when present, fall back to the file stem, and
    /// map the `Disabled` key to `enabled` (inverted). The first argument
    /// of `ProgramArguments` (or `Program`) becomes the candidate
    /// `appURL` for in-app "reveal in Finder".
    private func parseLaunchItem(at url: URL, type: StartupItemType, system: Bool) -> StartupItem {
        let dict = readPlist(at: url)
        let label = (dict["Label"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let disabled = (dict["Disabled"] as? Bool) ?? false
        let programPath: String?
        if let program = dict["Program"] as? String {
            programPath = program
        } else if let args = dict["ProgramArguments"] as? [String], let first = args.first {
            programPath = first
        } else {
            programPath = nil
        }
        let appURL: URL? = programPath.flatMap { path in
            // Only surface a non-nil URL when the path actually exists
            // (otherwise reveal-in-Finder would be a dead click).
            let candidate = URL(fileURLWithPath: path)
            return fileManager.fileExists(atPath: candidate.path) ? candidate : nil
        }
        return StartupItem(
            name: label,
            type: type,
            url: url,
            appURL: appURL,
            enabled: !disabled,
            isProtected: system
        )
    }

    /// Root of the per-user backup directory under Application Support.
    private func backupDirectory() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent("app.kraftly.kfresh")
            .appendingPathComponent("Backups")
            .appendingPathComponent("StartupItems")
    }
}
