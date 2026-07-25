import Foundation

actor BackupManager {
    private let fileManager = FileManager.default

    private var backupRoot: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("app.kraftly.kuninstall/Backups")
    }

    func backup(residues: [ResidueFile], bundleID: String) async throws -> URL {
        let backupDir = backupRoot.appendingPathComponent(bundleID)
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)

        for residue in residues where residue.confidence > 0.5 {
            let dest = backupDir.appendingPathComponent(residue.url.lastPathComponent)
            if fileManager.fileExists(atPath: residue.url.path) {
                try fileManager.copyItem(at: residue.url, to: dest)
            }
        }
        return backupDir
    }

    func restore(backupPath: URL, originalResidues: [ResidueFile]) async throws {
        for residue in originalResidues {
            let backupFile = backupPath.appendingPathComponent(residue.url.lastPathComponent)
            if fileManager.fileExists(atPath: backupFile.path) {
                try? fileManager.copyItem(at: backupFile, to: residue.url)
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
