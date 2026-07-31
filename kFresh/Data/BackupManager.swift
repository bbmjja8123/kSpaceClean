import Foundation

actor BackupManager {
    private let fileManager = FileManager.default

    private var backupRoot: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("app.kraftly.kfresh/Backups")
    }

    func backup(residues: [ResidueFile], bundleID: String) async throws -> URL {
        let backupDir = backupRoot.appendingPathComponent(bundleID)
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)

        for residue in residues where residue.confidence > 0.5 {
            let dest = backupDir.appendingPathComponent(residue.url.lastPathComponent)
            if fileManager.fileExists(atPath: residue.url.path) {
                // Overwrite an existing backup file at `dest` so a
                // re-run of backup (e.g. the test suite using a shared
                // backup root, or a user retrying an uninstall) does
                // not throw on a stale file. A backup must be the
                // authoritative copy of the source as it stands now.
                if fileManager.fileExists(atPath: dest.path) {
                    try fileManager.removeItem(at: dest)
                }
                try fileManager.copyItem(at: residue.url, to: dest)
            }
        }
        return backupDir
    }

    func restore(backupPath: URL, originalResidues: [ResidueFile]) async throws {
        for residue in originalResidues {
            let backupFile = backupPath.appendingPathComponent(residue.url.lastPathComponent)
            // Propagate copy errors so `TrashMover.restore` can detect a
            // partial restore and refuse to mark the record restored /
            // clean up the backup. The previous `try?` made the restore
            // path unable to signal failure to its caller (C1b).
            if fileManager.fileExists(atPath: backupFile.path) {
                // Remove any existing destination first — restore is
                // idempotent and must overwrite so a half-failed
                // previous restore attempt can be retried cleanly.
                if fileManager.fileExists(atPath: residue.url.path) {
                    try fileManager.removeItem(at: residue.url)
                }
                try fileManager.copyItem(at: backupFile, to: residue.url)
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
