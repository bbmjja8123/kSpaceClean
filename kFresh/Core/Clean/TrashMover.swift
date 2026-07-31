import Foundation
import AppKit

/// Errors surfaced by `TrashMover` to the uninstall UI layer.
///
/// `TrashMover` distinguishes between the three "soft" failure modes that
/// require user action (protected app, terminate timeout, overwrite refusal) and
/// the two "hard" failure modes that wrap an underlying `Error` from the OS
/// (trash move failed, audit log write failed). The UI uses the soft cases to
/// show a user-readable message; the hard cases are logged and shown as
/// "unexpected error" with the underlying `Error` attached for support.
public enum TrashError: Error {
    /// The app is system / Apple-protected and cannot be moved by policy.
    case protected(String)
    /// `NSWorkspace.recycle` (or a residue `removeItem`) threw.
    case trashFailed(underlying: Error)
    /// `NSRunningApplication.terminate` was called but the process did not
    /// exit within the configured timeout. The user must quit it manually.
    case terminateFailed(bundleID: String)
    /// The audit log write threw and the caller wants the failure surfaced
    /// (TrashMover currently swallows audit failures with `try?`).
    case auditLogFailed(underlying: Error)
    /// Restore was refused because the original path is already occupied by a
    /// different app. We never silently overwrite.
    case restoreRefusedOverwrite(path: String)
}

/// Safe-delete engine for uninstalling a Mac app and its residue files.
///
/// Three design properties distinguish this from a naive "move to Trash" loop:
///
/// 1. **Backup before delete**: residues are first copied into `BackupManager`
///    so a crash between the recycle call and the residue `removeItem` calls
///    does not lose user data. The backup is fully self-contained; restore
///    reads only from the backup directory.
/// 2. **Verify trash succeeded**: `NSWorkspace.recycle` is asynchronous, so
///    `TrashMover` re-checks the original path immediately after the call.
///    If the app is still there, the operation aborts and the backup is
///    preserved so a retry can succeed.
/// 3. **No silent overwrite on restore**: if the original install path is
///    already occupied (e.g. the user reinstalled the app), restore returns
///    `.restoreRefusedOverwrite` instead of `moveItem`-ing over the new copy.
///
/// `TrashMover` is an `actor`; all state mutations (`BackupManager`,
/// `UninstallHistoryRepository`, optional `AuditLogger`) are isolated.
public actor TrashMover {
    private let backupManager: BackupManager
    private let historyRepo: UninstallHistoryRepository
    private let auditLogger: AuditLogger?

    /// Creates a `TrashMover` with optional audit logging. When `auditLogger`
    /// is `nil`, the mover still works but no audit events are recorded.
    /// `BackupManager` and `UninstallHistoryRepository` are created with their
    /// default initialisers and live entirely inside this actor.
    public init(auditLogger: AuditLogger? = nil) {
        self.backupManager = BackupManager()
        self.historyRepo = UninstallHistoryRepository()
        self.auditLogger = auditLogger
    }

    /// Returns true if the app is allowed to be moved to Trash.
    ///
    /// System apps (`/System/*` and the `isBundleIDProtected` allowlist) and
    /// Apple-bundled com.apple.* apps are protected. All other sources
    /// (user-installed, App Store, unknown) are fair game.
    static func canMoveToTrash(app: InstalledApp) -> Bool {
        !app.isProtected
    }

    /// Uninstalled the given app and its residues, recording an audit trail.
    ///
    /// Order of operations:
    /// 1. Reject protected apps.
    /// 2. Gracefully terminate the running app (no forceTerminate).
    /// 3. Backup residues to `BackupManager`.
    /// 4. Recycle the app bundle to Trash.
    /// 5. Verify the original path is gone.
    /// 6. Delete residue files.
    /// 7. Save an `UninstallRecord` in history.
    /// 8. Log a `"trash"` audit event.
    func moveToTrash(app: InstalledApp, residues: [ResidueFile]) async -> Result<UninstallRecord, TrashError> {
        guard Self.canMoveToTrash(app: app) else {
            return .failure(.protected(app.protectionReason ?? "Protected by system policy"))
        }

        // Step 1: Terminate (graceful first; only force if user confirms)
        if app.isRunning {
            await terminateGracefully(app: app, timeoutSeconds: 8)
        }

        // Step 2: Backup residues FIRST (so we can recover even if recycle fails)
        var backupPath: URL?
        do {
            backupPath = try await backupManager.backup(residues: residues, bundleID: app.bundleID)
        } catch {
            await logEvent(action: "backup", bundleID: app.bundleID, paths: [], status: "failure", error: "\(error)")
            return .failure(.trashFailed(underlying: error))
        }

        // Step 3: Move app to trash
        do {
            try NSWorkspace.shared.recycle([app.url]) { _, _ in }
        } catch {
            await logEvent(action: "trash", bundleID: app.bundleID, paths: [app.url.path], status: "failure", error: "\(error)")
            return .failure(.trashFailed(underlying: error))
        }

        // Step 4: Verify trash succeeded (file no longer at original path).
        // NSWorkspace.recycle is documented as asynchronous; we sample the
        // filesystem immediately. This race window is documented in the
        // commit message — a stricter implementation could poll for a few
        // hundred milliseconds before declaring failure.
        if FileManager.default.fileExists(atPath: app.url.path) {
            await logEvent(action: "trash", bundleID: app.bundleID, paths: [app.url.path], status: "failure", error: "App still at original path after recycle")
            return .failure(.trashFailed(underlying: NSError(domain: "TrashMover", code: -1, userInfo: [NSLocalizedDescriptionKey: "Recycle verification failed"])))
        }

        // Step 5: Delete residues (now safe — backup already in place)
        for residue in residues where residue.confidence > 0.5 {
            try? FileManager.default.removeItem(at: residue.url)
        }

        let record = UninstallRecord(
            id: UUID(),
            appName: app.displayName,
            bundleID: app.bundleID,
            appPath: app.url.path,
            appSize: app.sizeBytes,
            totalResidueSize: residues.reduce(0) { $0 + $1.sizeBytes },
            residueCount: Int32(residues.count),
            uninstalledAt: Date(),
            isRestored: false,
            backupPath: backupPath?.path ?? "",
            residues: residues
        )
        await historyRepo.save(record: record)
        await logEvent(action: "trash", bundleID: app.bundleID, paths: [app.url.path] + residues.map(\.url.path), status: "success", error: nil)

        return .success(record)
    }

    /// Restores an app from Trash to its original install path.
    ///
    /// Behaviour:
    /// - Refuses to run if the original path is occupied (silent overwrite
    ///   would clobber a freshly-reinstalled app).
    /// - Moves the app bundle from `~/.Trash/<appName>` back to the original
    ///   path.
    /// - Restores residue files from the `BackupManager` snapshot.
    /// - Marks the history record as restored and cleans up the backup
    ///   directory.
    func restore(record: UninstallRecord) async -> Result<URL, TrashError> {
        let trashURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash")
            .appendingPathComponent(URL(fileURLWithPath: record.appPath).lastPathComponent)

        // Step 1: Refuse if original path already occupied (no silent overwrite)
        let originalURL = URL(fileURLWithPath: record.appPath)
        if FileManager.default.fileExists(atPath: originalURL.path) {
            await logEvent(action: "restore", bundleID: record.bundleID, paths: [originalURL.path], status: "failure", error: "Original path occupied")
            return .failure(.restoreRefusedOverwrite(path: originalURL.path))
        }

        // Step 2: Move app back from trash
        if FileManager.default.fileExists(atPath: trashURL.path) {
            do {
                try FileManager.default.moveItem(at: trashURL, to: originalURL)
            } catch {
                await logEvent(action: "restore", bundleID: record.bundleID, paths: [originalURL.path], status: "failure", error: "\(error)")
                return .failure(.trashFailed(underlying: error))
            }
        }

        // Step 3: Restore residues
        if !record.backupPath.isEmpty {
            let backupURL = URL(fileURLWithPath: record.backupPath)
            try? await backupManager.restore(backupPath: backupURL, originalResidues: record.residues)
        }

        await historyRepo.markRestored(id: record.id)
        await backupManager.cleanup(bundleID: record.bundleID)
        await logEvent(action: "restore", bundleID: record.bundleID, paths: [originalURL.path], status: "success", error: nil)

        return .success(originalURL)
    }

    /// Sends `terminate` to the app and waits up to `timeoutSeconds` for it
    /// to exit. **Never** force-terminates — `forceTerminate` is a one-way
    /// signal that loses unsaved user data. If the app does not exit within
    /// the timeout, a `"terminate-timeout"` audit event is logged and the
    /// uninstall proceeds; the user must quit the app manually.
    private func terminateGracefully(app: InstalledApp, timeoutSeconds: UInt64) async {
        let runningApps = NSWorkspace.shared.runningApplications
        guard let running = runningApps.first(where: { $0.bundleIdentifier == app.bundleID }) else { return }
        running.terminate()

        // Wait up to timeoutSeconds for graceful exit
        let deadline = Date().addingTimeInterval(Double(timeoutSeconds))
        while Date() < deadline {
            if running.isTerminated { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        // If still alive after timeout, log warning but DO NOT forceTerminate
        // (forceTerminate loses user data; user must explicitly force-quit via menu)
        await logEvent(action: "terminate-timeout", bundleID: app.bundleID, paths: [], status: "failure", error: "App did not exit gracefully within \(timeoutSeconds)s; user must quit manually")
    }

    /// Best-effort audit write. When no `AuditLogger` is configured the call
    /// is a no-op. When one is configured, write failures are swallowed so a
    /// failing audit log never blocks the uninstall.
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
        try? await logger.log(event)
    }
}

/// Persistent record of a successful uninstall. Stored in
/// `UninstallHistoryRepository` and used to back the History tab and the
/// restore flow. Internal (not `public`) because `ResidueFile` is internal — a
/// `public` wrapper around an internal type would not compile.
struct UninstallRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let appName: String
    let bundleID: String
    let appPath: String
    let appSize: Int64
    let totalResidueSize: Int64
    let residueCount: Int32
    let uninstalledAt: Date
    var isRestored: Bool
    let backupPath: String
    let residues: [ResidueFile]

    init(
        id: UUID,
        appName: String,
        bundleID: String,
        appPath: String,
        appSize: Int64,
        totalResidueSize: Int64,
        residueCount: Int32,
        uninstalledAt: Date,
        isRestored: Bool,
        backupPath: String,
        residues: [ResidueFile]
    ) {
        self.id = id
        self.appName = appName
        self.bundleID = bundleID
        self.appPath = appPath
        self.appSize = appSize
        self.totalResidueSize = totalResidueSize
        self.residueCount = residueCount
        self.uninstalledAt = uninstalledAt
        self.isRestored = isRestored
        self.backupPath = backupPath
        self.residues = residues
    }
}