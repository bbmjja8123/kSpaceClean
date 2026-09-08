// kWise/Features/StartupItems/StartupItemsScanner.swift
//
// 启动项管理 (M2, v2.0 Phase 5) — sandbox-legal scan + toggle.
//
// Mechanism (design decision D1):
// * **Scan** reads launch plists from `~/Library/LaunchAgents` (inside the
//   granted home scope via `PowerScopeProviding.withAccess`),
//   `/Library/LaunchAgents` and `/Library/LaunchDaemons` when world-readable.
// * **Toggle** is user-scope only: "disable" moves the plist to the Trash
//   through `TrashMover` — the TrashSnapshot gives free rollback and the
//   engine's 30-day history records the action. "enable" restores from the
//   recorded trash path. `launchctl` is never invoked (sandbox + review).
// * **System-scope items are read-only** — the UI shows a guidance card
//   instead of a fake switch (C-5).
// * kWise's own login item uses `SMAppService` (LoginItemService), not plists.
import Foundation
import PowerScope

// MARK: - Models

public enum ItemScope: String, Sendable, Codable {
    case user
    case system
}

public struct LoginItemEntry: Identifiable, Sendable, Codable {
    public let id: UUID
    /// plist filename without extension, e.g. `"com.spotify.client"`.
    public let label: String
    /// Absolute path of the plist (or the app bundle for app-based agents).
    public let plistURL: URL
    /// Program the agent launches (from `Program` / `ProgramArguments`).
    public let programPath: String?
    public let runAtLoad: Bool
    public let keepAlive: Bool
    public let scope: ItemScope

    public var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    public init(id: UUID = UUID(),
                label: String,
                plistURL: URL,
                programPath: String?,
                runAtLoad: Bool,
                keepAlive: Bool,
                scope: ItemScope) {
        self.id = id
        self.label = label
        self.plistURL = plistURL
        self.programPath = programPath
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.scope = scope
    }
}

/// One launch-agent plist parsed defensively — malformed files are skipped,
/// never thrown.
public enum LaunchPlistParser {
    /// A launch plist that exists but cannot be used — surfaced honestly in
    /// the 异常项 section instead of silently disappearing (C-5).
    public struct MalformedItem: Identifiable, Sendable {
        public let id = UUID()
        public let plistURL: URL
        public let reason: String
    }

    public static func parseMalformed(url: URL) -> MalformedItem? {
        let data = try? Data(contentsOf: url)
        let plist = data.flatMap { try? PropertyListSerialization.propertyList(
            from: $0, options: [], format: nil) as? [String: Any] }
        guard plist != nil else {
            return MalformedItem(plistURL: url, reason: "文件损坏或不是有效的 plist")
        }
        guard (plist?["Program"] as? String) != nil
                || (plist?["ProgramArguments"] as? [String]) != nil else {
            return MalformedItem(plistURL: url, reason: "缺少 Program / ProgramArguments，无法启动")
        }
        return nil
    }

    public static func parse(url: URL, scope: ItemScope) -> LoginItemEntry? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: Any]
        else { return nil }

        let label = (plist["Label"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let program = plist["Program"] as? String
            ?? (plist["ProgramArguments"] as? [String])?.first
        let runAtLoad = plist["RunAtLoad"] as? Bool ?? false
        // KeepAlive may be a Bool or a dictionary of conditions — any
        // non-nil value means "keep alive".
        let keepAlive: Bool
        if let flag = plist["KeepAlive"] as? Bool {
            keepAlive = flag
        } else if plist["KeepAlive"] is [String: Any] {
            keepAlive = true
        } else {
            keepAlive = false
        }

        return LoginItemEntry(
            label: label,
            plistURL: url,
            programPath: program,
            runAtLoad: runAtLoad,
            keepAlive: keepAlive,
            scope: scope
        )
    }
}

// MARK: - Scanner

/// Scans the three launch-item directories the sandbox permits.
public actor StartupItemsScanner {
    private let scope: any PowerScopeProviding

    public init(scope: any PowerScopeProviding) {
        self.scope = scope
    }

    public func scan() async -> (user: [LoginItemEntry], system: [LoginItemEntry], malformed: [LaunchPlistParser.MalformedItem]) {
        // User agents live inside the granted home scope.
        var userItems: [LoginItemEntry] = []
        let agentsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        var malformed: [LaunchPlistParser.MalformedItem] = []
        if let granted = try? await scope.withAccess(agentsURL, { $0 }) {
            userItems = Self.items(in: granted, scope: .user)
            malformed += Self.malformedItems(in: granted)
        }

        // System directories are world-readable; probe before reading.
        var systemItems: [LoginItemEntry] = []
        for dir in ["/Library/LaunchAgents", "/Library/LaunchDaemons"] {
            let url = URL(fileURLWithPath: dir, isDirectory: true)
            guard FileManager.default.isReadableFile(atPath: url.path) else { continue }
            systemItems += Self.items(in: url, scope: .system)
        }
        return (userItems, systemItems, malformed)
    }

    static func malformedItems(in directory: URL) -> [LaunchPlistParser.MalformedItem] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.pathExtension == "plist" }
            .compactMap { LaunchPlistParser.parseMalformed(url: $0) }
    }

    static func items(in directory: URL, scope: ItemScope) -> [LoginItemEntry] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.pathExtension == "plist" }
            .compactMap { LaunchPlistParser.parse(url: $0, scope: scope) }
            .sorted { $0.label < $1.label }
    }
}

// MARK: - Toggler

/// User-scope enable/disable. Disable = trash the plist (restorable);
/// enable = put it back. System-scope items are refused — the caller must
/// show guidance, not pretend (C-5).
public actor StartupItemToggler {
    private let mover: TrashMover
    private let persistence: PersistenceController

    public init(mover: TrashMover = TrashMover(),
                persistence: PersistenceController) {
        self.mover = mover
        self.persistence = persistence
    }

    /// Moves a user-level agent plist to the Trash and records history.
    /// - Returns: `false` when the entry was system-scope (refused).
    @discardableResult
    public func disable(_ entry: LoginItemEntry) async -> Bool {
        guard entry.scope == .user else { return false }
        guard FileManager.default.fileExists(atPath: entry.plistURL.path) else { return true }

        let result = await mover.moveToTrash(urls: [entry.plistURL])
        guard !result.snapshots.isEmpty else { return false }

        let context = persistence.newBackgroundContext()
        let snapshot = result.snapshots[0]
        let target = CleanupTarget(
            url: entry.plistURL,
            size: Self.sizeOf(entry.plistURL),
            risk: .caution,
            bundleID: entry.label
        )
        await context.perform { [persistence] in
            persistence.insertHistory(
                targets: [target],
                runID: UUID(),
                actionKind: CleanupHistoryItem.ActionKind.startupItem,
                in: context
            )
            persistence.save(context: context)
        }
        // Keep the trash mapping for restore.
        try? await TrashSnapshotStore.shared.store(snapshot)
        return true
    }

    /// Restores a previously disabled item from its Trash snapshot.
    /// - Returns: `false` when the entry was system-scope or the snapshot
    ///   is gone.
    @discardableResult
    public func enable(_ entry: LoginItemEntry) async -> Bool {
        guard entry.scope == .user else { return false }
        guard let snapshot = await TrashSnapshotStore.shared.snapshot(for: entry.plistURL.path)
        else { return false }

        let trashURL = URL(fileURLWithPath: snapshot.trashPath)
        let destination = URL(fileURLWithPath: snapshot.originalPath)
        guard FileManager.default.fileExists(atPath: trashURL.path) else { return false }

        do {
            try FileManager.default.moveItem(at: trashURL, to: destination)
            await TrashSnapshotStore.shared.remove(for: entry.plistURL.path)
            return true
        } catch {
            return false
        }
    }

    private static func sizeOf(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey])).flatMap { $0.fileSize.map(Int64.init) } ?? 0
    }
}

/// Ephemeral mapping original path → TrashSnapshot for startup-item restore.
/// Persists in the app support dir so "enable" works across relaunches
/// (within the 30-day retention window — Trash may empty it earlier, in
/// which case `enable` reports failure honestly).
public actor TrashSnapshotStore {
    public static let shared = TrashSnapshotStore()

    private var snapshots: [String: TrashSnapshot] = [:]
    private let fileURL: URL

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("app.kraftly.sclean", isDirectory: true)
        self.fileURL = dir.appendingPathComponent("startup-item-snapshots.json")
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([String: TrashSnapshot].self, from: data) {
            self.snapshots = stored
        }
    }

    public func store(_ snapshot: TrashSnapshot) async {
        snapshots[snapshot.originalPath] = snapshot
        persist()
    }

    public func snapshot(for originalPath: String) async -> TrashSnapshot? {
        snapshots[originalPath]
    }

    public func remove(for originalPath: String) async {
        snapshots.removeValue(forKey: originalPath)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
