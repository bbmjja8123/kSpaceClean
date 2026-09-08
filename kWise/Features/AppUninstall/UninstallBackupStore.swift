// kWise/Features/AppUninstall/UninstallBackupStore.swift
//
// 卸载前残留备份 (v2.3 Phase 4) — wraps AppCatalogCore's BackupManager with
// a kWise-scoped root. The engine's default root is kFresh-branded
// ("app.kraftly.kfresh/Backups") — kWise MUST pass its own container path.
//
// BackupManager's manifest deliberately stores only relative paths
// (portable across machines), so restore needs the original residue list.
// This store keeps a sidecar `residue-locations.json` per bundleID at
// backup time and rebuilds `[ResidueFile]` from it on restore.
import Foundation
import AppCatalogCore

/// Owns the kWise residue-backup lifecycle: backup before uninstall,
/// restore, 30-day TTL pruning.
actor UninstallBackupStore {
    /// kWise container Application Support — never the kFresh default.
    static func defaultRoot() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("app.kraftly.sclean/Backups", isDirectory: true)
    }

    /// Sidecar encoding — original residue locations per backup.
    private struct ResidueLocation: Codable {
        let path: String
        let confidence: Double
    }

    private let manager: BackupManager
    private let root: URL

    init(rootURL: URL? = nil) {
        let root = rootURL ?? Self.defaultRoot()
        self.root = root
        self.manager = BackupManager(rootURL: root)
    }

    /// Backs up the given residues before uninstall and records the original
    /// locations sidecar. Returns the backup directory (versioned `v<N>/`).
    @discardableResult
    func backupBeforeUninstall(entry: UninstallAppEntry) async throws -> URL {
        let backupURL = try await manager.backup(
            residues: entry.residues, bundleID: entry.bundleID
        )
        let locations = entry.residues.map { ResidueLocation(path: $0.url.path, confidence: $0.confidence) }
        if let data = try? JSONEncoder().encode(locations) {
            try? data.write(
                to: backupURL.appendingPathComponent("residue-locations.json"),
                options: .atomic
            )
        }
        return backupURL
    }

    /// Restores the latest backup for `bundleID` back to the recorded
    /// original residue locations. Throws honestly when no backup exists.
    func restoreLatest(bundleID: String) async throws {
        let bundleDir = root.appendingPathComponent(bundleID)
        guard let latest = Self.latestVersionedDirectory(in: bundleDir) else {
            throw BackupError.missingManifest(path: bundleDir.path)
        }
        let residues = try Self.residuesFromSidecar(at: latest)
        try await manager.restore(backupPath: latest, originalResidues: residues)
    }

    /// Deletes backups older than `days` (default matches the 30-day
    /// cleanup-history retention).
    @discardableResult
    func pruneExpired(days: Int = 30) async -> Int {
        await manager.cleanupExpired(olderThanDays: days)
    }

    // MARK: - Sidecar helpers

    private static func latestVersionedDirectory(in bundleDir: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: bundleDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.lastPathComponent.hasPrefix("v") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .first
    }

    private static func residuesFromSidecar(at backupDir: URL) throws -> [ResidueFile] {
        let sidecarURL = backupDir.appendingPathComponent("residue-locations.json")
        guard let data = try? Data(contentsOf: sidecarURL),
              let locations = try? JSONDecoder().decode([ResidueLocation].self, from: data)
        else {
            throw BackupError.corruptManifest(path: sidecarURL.path,
                                              underlying: NSError(domain: "UninstallBackupStore", code: 1))
        }
        return locations.map {
            ResidueFile(
                url: URL(fileURLWithPath: $0.path),
                type: .preferences,
                sizeBytes: 0,
                confidence: $0.confidence
            )
        }
    }
}
