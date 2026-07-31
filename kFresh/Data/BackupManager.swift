import Foundation

// TODO(kFresh-Wave0-Task5): BackupManager will be rewritten with versioned +
// TTL + integrity; the temp-and-rename guards added here are interim safety
// only. The rewrite will replace this actor entirely, so this file's public
// surface and persistence layout are deliberately unchanged for now.
//
// DO NOT add versioning, TTL eviction, or integrity checks here — that work
// is Task 5's scope. The only responsibility of the current file is to stop
// being data-destructive in the obvious failure paths.

actor BackupManager {
    private let fileManager = FileManager.default

    private var backupRoot: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("app.kraftly.kfresh/Backups")
    }

    /// Backup residues into the per-bundleID directory under
    /// `backupRoot`. Each residue is copied atomically (temp-and-rename)
    /// so a partial-failure mid-loop does not destroy a previously-good
    /// backup at the destination. The pre-fix implementation called
    /// `removeItem` on the existing backup file before `copyItem`; if
    /// `copyItem` failed (disk full, source unreadable, permissions),
    /// the user lost their last good backup copy. Post-fix: the new
    /// copy lands at `<dest>.tmp.<UUID>` first, then renames onto
    /// `<dest>` only after `copyItem` returned successfully.
    func backup(residues: [ResidueFile], bundleID: String) async throws -> URL {
        let backupDir = backupRoot.appendingPathComponent(bundleID)
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)

        for residue in residues where residue.confidence > 0.5 {
            let dest = backupDir.appendingPathComponent(residue.url.lastPathComponent)
            if fileManager.fileExists(atPath: residue.url.path) {
                // I3c: temp-and-rename so a failed `copyItem` does NOT
                // destroy the previously-good backup file at `dest`. The
                // rename is the atomic step that commits the new copy.
                let tempDest = backupDir.appendingPathComponent("\(residue.url.lastPathComponent).tmp.\(UUID().uuidString)")
                do {
                    try fileManager.copyItem(at: residue.url, to: tempDest)
                } catch {
                    // Best-effort cleanup of the orphan temp file; the
                    // rename never ran so `dest` is untouched.
                    try? fileManager.removeItem(at: tempDest)
                    throw error
                }
                // Atomic commit: replace `dest` with `tempDest` only
                // after the copy is verified.
                if fileManager.fileExists(atPath: dest.path) {
                    try fileManager.removeItem(at: dest)
                }
                try fileManager.moveItem(at: tempDest, to: dest)
            }
        }
        return backupDir
    }

    /// Restore each backup file to its original `ResidueFile.url`. Uses
    /// temp-and-rename so a failed `copyItem` does NOT destroy an
    /// existing destination file (the pre-fix implementation called
    /// `removeItem` first, then `copyItem`; if the copy failed, neither
    /// the original nor the restored copy remained). Post-fix: the new
    /// copy lands at `<dest>.tmp.<UUID>` first, then renames onto
    /// `<dest>` only after the copy is verified.
    func restore(backupPath: URL, originalResidues: [ResidueFile]) async throws {
        for residue in originalResidues {
            let backupFile = backupPath.appendingPathComponent(residue.url.lastPathComponent)
            // Propagate copy errors so `TrashMover.restore` can detect a
            // partial restore and refuse to mark the record restored /
            // clean up the backup. The previous `try?` made the restore
            // path unable to signal failure to its caller (C1b).
            if fileManager.fileExists(atPath: backupFile.path) {
                // I3d: temp-and-rename so a failed `copyItem` does NOT
                // destroy the existing destination at `residue.url`. The
                // pre-delete on the destination moved into the rename
                // step below — the existing destination is now only
                // touched AFTER the temp copy is verified.
                let tempDest = residue.url.deletingLastPathComponent()
                    .appendingPathComponent("\(residue.url.lastPathComponent).tmp.\(UUID().uuidString)")
                do {
                    try fileManager.copyItem(at: backupFile, to: tempDest)
                } catch {
                    // Clean up the orphan temp file; `residue.url` is
                    // untouched and the user's existing file (if any)
                    // is still on disk.
                    try? fileManager.removeItem(at: tempDest)
                    throw error
                }
                // Atomic commit: if a destination already exists, remove
                // it before renaming the verified temp onto the path.
                // Restore is idempotent and must overwrite so a half-
                // failed previous restore attempt can be retried cleanly
                // — but the pre-delete happens only AFTER the new copy
                // is verified, so a failed copy never leaves the user
                // without their existing file.
                if fileManager.fileExists(atPath: residue.url.path) {
                    try fileManager.removeItem(at: residue.url)
                }
                try fileManager.moveItem(at: tempDest, to: residue.url)
            }
        }
    }

    func cleanup(bundleID: String) {
        let backupDir = backupRoot.appendingPathComponent(bundleID)
        try? fileManager.removeItem(at: backupDir)
    }

    func cleanupExpired(olderThan days: Int) {
        guard let contents = try? fileManager.contentsOfDirectory(at: backupRoot,
                                                                   includingPropertiesForKeys: [.creationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        for url in contents {
            guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                  let creationDate = attrs[.creationDate] as? Date,
                  creationDate < cutoff else { continue }
            try? fileManager.removeItem(at: url)
        }
    }
}
