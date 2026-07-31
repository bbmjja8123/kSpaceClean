import Foundation
import AppKit

/// Errors surfaced by `TrashMover` to the uninstall UI layer.
///
/// `TrashMover` distinguishes between the four "soft" failure modes that
/// require user action (protected app, terminate timeout, overwrite refusal,
/// trashed item missing) and the two "hard" failure modes that wrap an
/// underlying `Error` from the OS (trash move failed, audit log write
/// failed). The UI uses the soft cases to show a user-readable message; the
/// hard cases are logged and shown as "unexpected error" with the underlying
/// `Error` attached for support.
public enum TrashError: Error {
    /// The app is system / Apple-protected and cannot be moved by policy.
    case protected(String)
    /// `FileManager.trashItem` (or a residue `removeItem`) threw.
    case trashFailed(underlying: Error)
    /// `NSRunningApplication.terminate` was called but the process did not
    /// exit within the configured timeout. The user must quit it manually.
    case terminateFailed(bundleID: String)
    /// The audit log write threw and the caller wants the failure surfaced.
    /// Currently declared for forward-compatibility: `TrashMover.logEvent`
    /// still swallows `AuditLogger` write errors so an audit failure cannot
    /// block an otherwise-successful uninstall.
    case auditLogFailed(underlying: Error)
    /// Restore was refused because the original path is already occupied by
    /// a different app. We never silently overwrite.
    case restoreRefusedOverwrite(path: String)
    /// Restore could not proceed because the trashed item is no longer in
    /// Trash (the user emptied the Trash, or Finder de-duplicated the
    /// bundle name on a prior uninstall). Restoring from an empty Trash
    /// would silently destroy the backup, so we refuse explicitly.
    case trashedItemMissing(bundleID: String)
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
    /// 2. Gracefully terminate the running app (no forceTerminate). If the
    ///    graceful terminate does not complete within the timeout, the
    ///    operation aborts with `.terminateFailed` so the user can either
    ///    wait or quit manually — recycling a still-running process races the
    ///    filesystem and risks audit-log garbage.
    /// 3. Backup residues to `BackupManager`.
    /// 4. Recycle the app bundle to Trash via `FileManager.trashItem`, which
    ///    is synchronous, throws on failure, and returns the actual
    ///    resulting URL inside `~/.Trash` (which Finder may have
    ///    de-duplicated, e.g. `Foo.app` → `Foo 2.app`). The resulting URL is
    ///    persisted on `UninstallRecord.actualTrashPath` so restore uses
    ///    the exact path Finder produced instead of guessing.
    /// 5. Delete the FILTERED set of high-confidence residue files. Per-
    ///    residue failures are collected; residue counts reported in the
    ///    record and audit event reflect the filtered set actually deleted,
    ///    never the full input.
    /// 6. Save an `UninstallRecord` in history.
    /// 7. Log a `"trash"` audit event.
    func moveToTrash(app: InstalledApp, residues: [ResidueFile]) async -> Result<UninstallRecord, TrashError> {
        guard Self.canMoveToTrash(app: app) else {
            return .failure(.protected(app.protectionReason ?? "Protected by system policy"))
        }

        // Step 1: Terminate (graceful first; only force if user confirms)
        if app.isRunning {
            do {
                try await terminateGracefully(app: app, timeoutSeconds: 8)
            } catch let TrashError.terminateFailed(bundleID) {
                await logEvent(action: "terminate", bundleID: bundleID, paths: [app.url.path], status: "failure", error: "App did not exit gracefully")
                return .failure(TrashError.terminateFailed(bundleID: bundleID))
            } catch {
                return .failure(.trashFailed(underlying: error))
            }
        }

        // Step 2: Backup residues FIRST (so we can recover even if recycle fails)
        var backupPath: URL?
        do {
            backupPath = try await backupManager.backup(residues: residues, bundleID: app.bundleID)
        } catch {
            await logEvent(action: "backup", bundleID: app.bundleID, paths: [], status: "failure", error: "\(error)")
            return .failure(.trashFailed(underlying: error))
        }

        // Step 3: Move app to trash via FileManager.trashItem. This is
        // synchronous and throws on failure, so we no longer rely on the
        // post-hoc `fileExists` race against an async recycle call. The
        // `resultingItemURL` out-parameter captures the Finder-actual path
        // (with `Foo 2.app` style deduplication applied), which restore
        // needs to find the item again later.
        var resultingTrashURL: NSURL?
        do {
            try FileManager.default.trashItem(at: app.url, resultingItemURL: &resultingTrashURL)
        } catch {
            await logEvent(action: "trash", bundleID: app.bundleID, paths: [app.url.path], status: "failure", error: "\(error)")
            return .failure(.trashFailed(underlying: error))
        }
        guard let trashedURL = resultingTrashURL as URL? else {
            await logEvent(action: "trash", bundleID: app.bundleID, paths: [app.url.path], status: "failure", error: "Trash completed but no resulting URL returned")
            return .failure(.trashFailed(underlying: NSError(domain: "TrashMover", code: -1, userInfo: [NSLocalizedDescriptionKey: "Trash returned no resulting URL"])))
        }

        // Step 4: Delete the FILTERED high-confidence residues. Per-residue
        // errors are collected (never silently swallowed) and surfaced in
        // the audit event. The record and success audit only report the
        // residues we actually deleted.
        let filteredResidues = residues.filter { $0.confidence > 0.5 }
        var residueFailures: [(url: URL, error: Error)] = []
        for residue in filteredResidues {
            do {
                try FileManager.default.removeItem(at: residue.url)
            } catch {
                residueFailures.append((residue.url, error))
            }
        }

        // Step 5: Build the success record from the filtered set.
        let record = UninstallRecord(
            id: UUID(),
            appName: app.displayName,
            bundleID: app.bundleID,
            appPath: app.url.path,
            actualTrashPath: trashedURL.path,
            appSize: app.sizeBytes,
            totalResidueSize: filteredResidues.reduce(0) { $0 + $1.sizeBytes },
            residueCount: Int32(filteredResidues.count),
            uninstalledAt: Date(),
            isRestored: false,
            backupPath: backupPath?.path ?? "",
            residues: filteredResidues
        )
        await historyRepo.save(record: record)

        // Audit: success event logs all filtered residue paths and any
        // per-residue failures as a single comma-separated errorMessage so
        // the operator can reconstruct exactly what happened.
        let auditPaths = [app.url.path] + filteredResidues.map(\.url.path)
        let residueErrorMessage: String?
        if residueFailures.isEmpty {
            residueErrorMessage = nil
        } else {
            let details = residueFailures.map { "\($0.url.path): \($0.error)" }.joined(separator: "; ")
            residueErrorMessage = "\(residueFailures.count)/\(filteredResidues.count) residues failed: \(details)"
        }
        await logEvent(action: "trash", bundleID: app.bundleID, paths: auditPaths, status: "success", error: residueErrorMessage)

        return .success(record)
    }

    /// Restores an app from Trash to its original install path.
    ///
    /// Behaviour:
    /// - Refuses to run if the original path is occupied (silent overwrite
    ///   would clobber a freshly-reinstalled app).
    /// - Resolves the trashed item via `UninstallRecord.actualTrashPath`
    ///   (captured at uninstall time after Finder de-duplication) instead
    ///   of guessing `~/.Trash/<bundleName>`. If that path does not exist
    ///   (Trash was emptied, or the path was guessed wrong), returns
    ///   `.trashedItemMissing` WITHOUT touching the backup or marking the
    ///   record restored — this prevents silent destruction of the residue
    ///   backup when the actual trashed item is gone.
    /// - Moves the app bundle back to the original path.
    /// - Restores residue files from the `BackupManager` snapshot.
    /// - Marks the history record as restored AND cleans up the backup
    ///   directory only after both moves succeed.
    func restore(record: UninstallRecord) async -> Result<URL, TrashError> {
        let originalURL = URL(fileURLWithPath: record.appPath)

        // Step 1: Refuse if original path already occupied (no silent overwrite)
        if FileManager.default.fileExists(atPath: originalURL.path) {
            await logEvent(action: "restore", bundleID: record.bundleID, paths: [originalURL.path], status: "failure", error: "Original path occupied")
            return .failure(.restoreRefusedOverwrite(path: originalURL.path))
        }

        // Step 2: Resolve the actual trashed path captured at uninstall
        // time. If we have no recorded trash path (older record format),
        // fall back to the conventional guess as a best-effort, but only
        // IF that guess exists on disk.
        let trashURL: URL
        if !record.actualTrashPath.isEmpty {
            trashURL = URL(fileURLWithPath: record.actualTrashPath)
        } else {
            trashURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".Trash")
                .appendingPathComponent(URL(fileURLWithPath: record.appPath).lastPathComponent)
        }
        guard FileManager.default.fileExists(atPath: trashURL.path) else {
            // Missing trashed item is a soft failure — refuse explicitly
            // and leave the backup intact so the user can still recover
            // residues (or attempt manual restore) instead of silently
            // destroying the only copy of their data.
            await logEvent(action: "restore", bundleID: record.bundleID, paths: [trashURL.path], status: "failure", error: "Trashed item missing (Trash emptied?)")
            return .failure(.trashedItemMissing(bundleID: record.bundleID))
        }

        // Step 3: Move app back from trash
        do {
            try FileManager.default.moveItem(at: trashURL, to: originalURL)
        } catch {
            await logEvent(action: "restore", bundleID: record.bundleID, paths: [originalURL.path], status: "failure", error: "\(error)")
            return .failure(.trashFailed(underlying: error))
        }

        // Step 4: Restore residues
        if !record.backupPath.isEmpty {
            let backupURL = URL(fileURLWithPath: record.backupPath)
            try? await backupManager.restore(backupPath: backupURL, originalResidues: record.residues)
        }

        // Step 5: Only mark restored + clean up backup AFTER both moves
        // succeed. Doing this earlier was the C1 bug — a missing trashed
        // item used to fall through to here and delete the residue backup
        // while pretending the restore succeeded.
        await historyRepo.markRestored(id: record.id)
        await backupManager.cleanup(bundleID: record.bundleID)
        await logEvent(action: "restore", bundleID: record.bundleID, paths: [originalURL.path], status: "success", error: nil)

        return .success(originalURL)
    }

    /// Sends `terminate` to the app and waits up to `timeoutSeconds` for it
    /// to exit. **Never** force-terminates — `forceTerminate` is a one-way
    /// signal that loses unsaved user data. If the app does not exit within
    /// the timeout, throws `TrashError.terminateFailed(bundleID:)` so the
    /// caller can surface a "user must quit manually" error to the UI
    /// instead of proceeding to recycle a live process.
    private func terminateGracefully(app: InstalledApp, timeoutSeconds: UInt64) async throws {
        let runningApps = NSWorkspace.shared.runningApplications
        guard let running = runningApps.first(where: { $0.bundleIdentifier == app.bundleID }) else { return }
        running.terminate()

        // Wait up to timeoutSeconds for graceful exit
        let deadline = Date().addingTimeInterval(Double(timeoutSeconds))
        while Date() < deadline {
            if running.isTerminated { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        // Still alive after timeout — refuse to recycle a live process.
        // Logging is left to the caller (moveToTrash) so the bundleID is
        // attached to the right structured event.
        throw TrashError.terminateFailed(bundleID: app.bundleID)
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
    /// The exact path inside `~/.Trash` where the bundle landed after
    /// `FileManager.trashItem` completed — populated by `moveToTrash`
    /// from the recycle call's `resultingItemURL`. Necessary because
    /// Finder renames duplicates on the way in (e.g. `Foo.app` →
    /// `Foo 2.app`), so restore cannot infer this from `appPath`
    /// alone. Empty string for legacy records predating this field.
    let actualTrashPath: String
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
        actualTrashPath: String = "",
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
        self.actualTrashPath = actualTrashPath
        self.appSize = appSize
        self.totalResidueSize = totalResidueSize
        self.residueCount = residueCount
        self.uninstalledAt = uninstalledAt
        self.isRestored = isRestored
        self.backupPath = backupPath
        self.residues = residues
    }
}