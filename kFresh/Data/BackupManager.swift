import Foundation
import CommonCrypto

/// Versioned, integrity-checked backup store for uninstall residue.
///
/// `BackupManager` is responsible for the safety net behind every uninstall:
/// before `TrashMover` removes residue files, the residue is copied into a
/// per-bundleID directory under `rootURL` so a failed uninstall can be
/// reversed. This rewrite adds three guarantees the pre-rewrite actor did
/// not have:
///
/// 1. **Versioning** — every call to ``backup(residues:bundleID:)`` creates
///    a new `v<N>/` subdirectory inside the bundle's directory. `N` is
///    one greater than the highest pre-existing version number, so repeated
///    backups remain collision-free even when a middle version is missing.
/// 2. **30-day TTL eviction** — ``cleanupExpired(olderThanDays:)`` walks
///    `rootURL`, removes any bundleID directory whose `creationDate` is
///    older than the cutoff, and returns the count removed. ``cleanup(bundleID:)``
///    removes all versions for one bundleID unconditionally (used after a
///    successful restore).
/// 3. **Integrity check** — every backed-up file is hashed with
///    `SHA-256` at backup time and the digest is written into
///    `manifest.json` alongside the relative path and size. ``verify(backupPath:)``
///    re-reads the manifest and re-hashes every file to detect silent
///    corruption between `backup` and `restore`.
///
/// The atomic-write guarantee from the I3c/I3d interim fixes is preserved:
/// every file write goes through a temporary copy followed by an atomic
/// replacement (`<dest>.tmp.<UUID>` → `replaceItemAt`) so failed copies or
/// replacements do not pre-delete the destination already on disk.
///
/// `BackupManager` is an `actor`; all state mutations are serialised on the
/// actor's executor so concurrent calls from `TrashMover` cannot race.
public actor BackupManager {

    // MARK: - Manifest

    /// Per-backup manifest written to `manifest.json` at backup time.
    ///
    /// Stored inside each versioned `v<N>/` directory so `verify` can
    /// re-check the contents without any external index. Encoded with
    /// `JSONEncoder` and read back with `JSONDecoder`; both are
    /// `Codable`-round-trip stable.
    public struct Manifest: Codable, Sendable {
        /// Schema version for forward compatibility. Currently always `1`.
        public let schemaVersion: Int
        /// Bundle identifier this backup belongs to.
        public let bundleID: String
        /// When the backup was taken.
        public let createdAt: Date
        /// Monotonic version number (`1` for the first backup, `2` for the
        /// second, etc.). The number is local to this bundleID directory.
        public let version: Int
        /// One entry per backed-up file.
        public let files: [ManifestEntry]

        /// Creates a manifest for one versioned backup.
        public init(
            schemaVersion: Int = 1,
            bundleID: String,
            createdAt: Date,
            version: Int,
            files: [ManifestEntry]
        ) {
            self.schemaVersion = schemaVersion
            self.bundleID = bundleID
            self.createdAt = createdAt
            self.version = version
            self.files = files
        }

        /// Decodes manifests while treating the absent schema field in legacy
        /// JSON as schema version `1`.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            do {
                schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            } catch {
                print("BackupManager.Manifest: invalid schemaVersion, defaulting to 1: \(error)")
                schemaVersion = 1
            }
            bundleID = try container.decode(String.self, forKey: .bundleID)
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            version = try container.decode(Int.self, forKey: .version)
            files = try container.decode([ManifestEntry].self, forKey: .files)
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case bundleID
            case createdAt
            case version
            case files
        }

        /// Description of one file inside a backup.
        public struct ManifestEntry: Codable, Sendable {
            /// File name (`lastPathComponent`) relative to the versioned
            /// directory. We deliberately store only the file name and not
            /// a full path so a backup is portable across machines whose
            /// absolute paths differ.
            public let relativePath: String
            /// File size in bytes at backup time.
            public let sizeBytes: Int64
            /// Lowercase hex SHA-256 of the file at backup time.
            public let sha256: String

            /// Creates one manifest entry.
            public init(relativePath: String, sizeBytes: Int64, sha256: String) {
                self.relativePath = relativePath
                self.sizeBytes = sizeBytes
                self.sha256 = sha256
            }
        }
    }

    // MARK: - Stored state

    /// `FileManager` used for all filesystem operations. Held as a stored
    /// property so a future test can inject a non-default instance.
    private let fileManager: FileManager
    /// Directory under which all backups live. Either explicitly provided
    /// by the caller (tests, custom deployments) or derived from
    /// `applicationSupportDirectory` + the bundle ID in ``defaultRootURL()``.
    private let rootURL: URL

    // MARK: - Init

    /// Creates a backup manager rooted at `rootURL`. If `rootURL` is `nil`,
    /// the manager uses the production default:
    /// `applicationSupportDirectory/app.kraftly.kfresh/Backups`.
    ///
    /// - Parameter rootURL: Override location for backup storage. Tests
    ///   pass a unique `temporaryDirectory.appendingPathComponent(...)`
    ///   here so the production root is never touched.
    public init(rootURL: URL? = nil) {
        self.fileManager = .default
        self.rootURL = rootURL ?? Self.defaultRootURL()
    }

    /// Returns the production root, or `NSTemporaryDirectory()` if
    /// `applicationSupportDirectory` is unavailable.
    private static func defaultRootURL() -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                        in: .userDomainMask).first else {
            // Fall back to a /tmp location so the actor never crashes on
            // construction. The caller will see the failure on the first
            // backup call when the disk write throws.
            return URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("app.kraftly.kfresh/Backups")
        }
        return appSupport.appendingPathComponent("app.kraftly.kfresh/Backups")
    }

    // MARK: - Backup

    /// Copies each residue into a new versioned subdirectory and writes a
    /// `manifest.json` describing the contents + SHA-256 of every file.
    ///
    /// Returns the URL of the new `v<N>/` directory. The caller passes this
    /// URL to ``restore(backupPath:originalResidues:)`` when (and if) the
    /// user requests a restore.
    ///
    /// Residues with `confidence <= 0.5` are skipped — the residue detector
    /// is intentionally conservative so the backup store does not bloat
    /// with low-signal paths. Missing source files are skipped too (a
    /// residue might have been moved between scan and backup).
    ///
    /// - Parameter residues: Residue files detected by `ResidueDetector`.
    /// - Parameter bundleID: Bundle identifier whose backup directory is
    ///   `rootURL/<bundleID>/`.
    /// - Returns: URL of the newly-created versioned directory.
    /// - Throws: Filesystem errors from `createDirectory` or the copy loop.
    public func backup(residues: [ResidueFile], bundleID: String) async throws -> URL {
        let bundleDir = rootURL.appendingPathComponent(bundleID)
        let existingVersions = listVersionedDirectories(in: bundleDir)
        let versionNumbers = existingVersions.compactMap { url in
            Int(url.lastPathComponent.dropFirst())
        }
        let version = (versionNumbers.max() ?? 0) + 1
        let backupDir = bundleDir.appendingPathComponent("v\(version)")
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)

        var entries: [Manifest.ManifestEntry] = []

        for residue in residues where residue.confidence > 0.5 {
            guard fileManager.fileExists(atPath: residue.url.path) else { continue }
            let fileName = residue.url.lastPathComponent
            let dest = backupDir.appendingPathComponent(fileName)

            // Temp-and-atomic-replacement: copy lands at
            // `<dest>.tmp.<UUID>` first. A failed copy or replacement leaves
            // any previous good backup at `dest` untouched (I3c).
            let tempDest = backupDir.appendingPathComponent("\(fileName).tmp.\(UUID().uuidString)")
            do {
                try fileManager.copyItem(at: residue.url, to: tempDest)
            } catch {
                do {
                    try fileManager.removeItem(at: tempDest)
                } catch {
                    // Orphan temp; safe to leave — `moveItem` below never ran.
                    print("BackupManager.backup: failed to clean orphan temp \(tempDest.path): \(error)")
                }
                throw error
            }
            do {
                _ = try fileManager.replaceItemAt(
                    dest,
                    withItemAt: tempDest,
                    backupItemName: nil,
                    options: .usingNewMetadataOnly
                )
            } catch {
                do {
                    try fileManager.removeItem(at: tempDest)
                } catch {
                    print("BackupManager.backup: failed to clean orphan temp after replace failure \(tempDest.path): \(error)")
                }
                throw error
            }

            // Hash the file we just wrote so the manifest can be used by
            // `verify` later. We read from `dest` (the canonical location)
            // rather than `tempDest` because we want the hash of what is on
            // disk, not the temp file we are about to delete.
            let data = try Data(contentsOf: dest)
            let sha = Self.sha256Hex(data)
            entries.append(Manifest.ManifestEntry(
                relativePath: fileName,
                sizeBytes: Int64(data.count),
                sha256: sha
            ))
        }

        let manifest = Manifest(bundleID: bundleID, createdAt: Date(), version: version, files: entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: backupDir.appendingPathComponent("manifest.json"))

        return backupDir
    }

    // MARK: - Restore

    /// Copies every file named in `manifest.json` from `backupPath` back
    /// to its original `ResidueFile.url`, skipping entries whose
    /// destination is at least as large as the backup's recorded size (the
    /// "more-recent file" heuristic — see the warning below).
    ///
    /// The backup directory is expected to be the `v<N>/` URL returned by
    /// ``backup(residues:bundleID:)``. If the manifest is missing or
    /// malformed the function throws `BackupError.missingManifest` /
    /// `.corruptManifest` so the caller can surface the failure rather
    /// than silently no-op.
    ///
    /// **Important**: "skip when the current file is larger" is a
    /// best-effort heuristic, not a content comparison. A user who edits
    /// a residue file to be SMALLER than the backup will have it
    /// overwritten on restore. We deliberately do not compare mtimes
    /// because residue files routinely have stale mtimes; size is the
    /// only signal we trust without trusting the filesystem.
    ///
    /// - Parameter backupPath: `v<N>/` directory URL previously returned
    ///   by ``backup(residues:bundleID:)``.
    /// - Parameter originalResidues: The residue set the user originally
    ///   backed up; used to look up destination URLs by file name.
    /// - Throws: `BackupError.missingManifest`, `.corruptManifest`, or
    ///   filesystem errors from the copy loop.
    public func restore(backupPath: URL, originalResidues: [ResidueFile]) async throws {
        let manifest = try Self.readManifest(at: backupPath, fileManager: fileManager)

        for entry in manifest.files {
            guard let residue = originalResidues.first(where: { $0.url.lastPathComponent == entry.relativePath }) else { continue }
            let backupFile = backupPath.appendingPathComponent(entry.relativePath)
            guard fileManager.fileExists(atPath: backupFile.path) else {
                print("BackupManager.restore: manifest entry references missing file \(entry.relativePath) in \(backupPath.path)")
                continue
            }

            // CRITICAL: never overwrite a more-recent file at the original
            // path. The "more recent" heuristic is "current size >= backup
            // size" — see the warning in the DocC above for why we don't
            // compare mtimes.
            if fileManager.fileExists(atPath: residue.url.path) {
                let existingSize: Int64
                do {
                    let attrs = try fileManager.attributesOfItem(atPath: residue.url.path)
                    if let size = attrs[.size] as? Int64 {
                        existingSize = size
                    } else if let size = attrs[.size] as? NSNumber {
                        existingSize = size.int64Value
                    } else {
                        // Treat unreadable size as "zero" so restore still
                        // proceeds — better to overwrite a corruptly-
                        // stat'd file than to leave the user stuck.
                        existingSize = 0
                    }
                } catch {
                    // attributesOfItem can throw for EACCES on the
                    // directory — treat as zero so the restore path can
                    // continue.
                    existingSize = 0
                }
                if existingSize >= entry.sizeBytes { continue }
            }

            // Temp-and-atomic-replacement: copy lands at
            // `<dest>.tmp.<UUID>` first. A failed copy or replacement leaves
            // the existing destination untouched (I3d).
            let dest = residue.url
            let tempDest = dest.deletingLastPathComponent()
                .appendingPathComponent("\(dest.lastPathComponent).tmp.\(UUID().uuidString)")
            do {
                try fileManager.copyItem(at: backupFile, to: tempDest)
            } catch {
                do {
                    try fileManager.removeItem(at: tempDest)
                } catch {
                    print("BackupManager.restore: failed to clean orphan temp \(tempDest.path): \(error)")
                }
                throw error
            }
            do {
                _ = try fileManager.replaceItemAt(
                    dest,
                    withItemAt: tempDest,
                    backupItemName: nil,
                    options: .usingNewMetadataOnly
                )
            } catch {
                // Atomic replace failed; the original destination was never
                // pre-deleted. Clean up the temporary copy and propagate.
                do {
                    try fileManager.removeItem(at: tempDest)
                } catch {
                    print("BackupManager.restore: failed to clean orphan temp \(tempDest.path): \(error)")
                }
                throw error
            }
        }
    }

    // MARK: - Cleanup

    /// Removes every version of the backup for `bundleID`. Called by
    /// `TrashMover` after a successful restore so the user's disk does not
    /// fill up with restore-history copies.
    ///
    /// Errors are logged but not thrown — cleanup is best-effort and the
    /// user-visible flow should not block on a stale directory the next
    /// backup will overwrite anyway.
    ///
    /// - Parameter bundleID: Bundle identifier whose directory under
    ///   `rootURL` should be removed.
    public func cleanup(bundleID: String) async {
        let bundleDir = rootURL.appendingPathComponent(bundleID)
        do {
            try fileManager.removeItem(at: bundleDir)
        } catch {
            // ENOENT (already removed) is fine; anything else is logged via
            // `print` (visible in `Console.app` only during a foreground
            // debug session) but does not block the calling flow.
            print("BackupManager.cleanup: failed to remove \(bundleDir.path): \(error)")
        }
    }

    /// Removes every bundleID directory under `rootURL` whose
    /// `creationDate` is older than `days` days. Returns the count
    /// removed. Versioned `v<N>/` subdirectories move with their parent,
    /// so removing the bundle directory is sufficient.
    ///
    /// - Parameter days: Age cutoff in days; directories older than this
    ///   are removed.
    /// - Returns: Number of bundleID directories removed.
    public func cleanupExpired(olderThanDays days: Int) async -> Int {
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(at: rootURL,
                                                           includingPropertiesForKeys: [.creationDateKey])
        } catch {
            print("BackupManager.cleanupExpired: failed to list \(rootURL.path): \(error)")
            return 0
        }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        var removed = 0
        for url in contents {
            let attrs: [FileAttributeKey: Any]
            do {
                attrs = try fileManager.attributesOfItem(atPath: url.path)
            } catch {
                print("BackupManager.cleanupExpired: failed to inspect \(url.path): \(error)")
                continue
            }
            guard let creationDate = attrs[.creationDate] as? Date,
                  creationDate < cutoff else { continue }
            do {
                try fileManager.removeItem(at: url)
                removed += 1
            } catch {
                print("BackupManager.cleanupExpired: failed to remove \(url.path): \(error)")
            }
        }
        return removed
    }

    // MARK: - Verify

    /// Reads `manifest.json` from `backupPath` and re-hashes every file,
    /// returning `true` only when every digest matches and every file is
    /// readable. Returns `false` (and never throws) when the manifest is
    /// missing, malformed, or any file has been corrupted.
    ///
    /// - Parameter backupPath: `v<N>/` directory URL previously returned
    ///   by ``backup(residues:bundleID:)``.
    /// - Returns: `true` if every manifest entry matches the file on disk.
    public func verify(backupPath: URL) async throws -> Bool {
        let manifest: Manifest
        do {
            manifest = try Self.readManifest(at: backupPath, fileManager: fileManager)
        } catch {
            // Missing or unreadable manifest → backup is not verifiable,
            // treat as invalid rather than throwing so callers can branch
            // on a single Bool.
            print("BackupManager.verify: manifest unreadable at \(backupPath.path): \(error)")
            return false
        }
        for entry in manifest.files {
            let fileURL = backupPath.appendingPathComponent(entry.relativePath)
            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
            } catch {
                print("BackupManager.verify: file unreadable at \(fileURL.path): \(error)")
                return false
            }
            if Self.sha256Hex(data) != entry.sha256 {
                print("BackupManager.verify: hash mismatch for \(entry.relativePath)")
                return false
            }
        }
        return true
    }

    // MARK: - Helpers

    /// Returns the `v<N>/` directories that already exist in `bundleDir`,
    /// excluding any non-versioned entries. Returns an empty list when the
    /// bundle directory does not yet exist (the common first-backup case).
    private func listVersionedDirectories(in bundleDir: URL) -> [URL] {
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(at: bundleDir,
                                                           includingPropertiesForKeys: nil)
        } catch {
            if fileManager.fileExists(atPath: bundleDir.path) {
                print("BackupManager.listVersionedDirectories: failed to list \(bundleDir.path): \(error)")
            }
            return []
        }
        return contents.filter { $0.lastPathComponent.hasPrefix("v") }
    }

    /// Reads and decodes `manifest.json` from `backupPath`. Used by both
    /// ``restore(backupPath:originalResidues:)`` and ``verify(backupPath:)``.
    /// Throws on missing file, unreadable file, or undecodable JSON.
    private static func readManifest(at backupPath: URL, fileManager: FileManager) throws -> Manifest {
        let manifestURL = backupPath.appendingPathComponent("manifest.json")
        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            throw BackupError.missingManifest(path: manifestURL.path)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Manifest.self, from: data)
        } catch {
            throw BackupError.corruptManifest(path: manifestURL.path, underlying: error)
        }
    }

    /// Returns the lowercase hex SHA-256 of `data` for test fixtures.
    static func sha256HexForTest(_ data: Data) -> String {
        sha256Hex(data)
    }

    /// Returns the lowercase hex SHA-256 of `data`.
    private static func sha256Hex(_ data: Data) -> String {
        sha256CC(data).map { String(format: "%02x", $0) }.joined()
    }

    /// CommonCrypto SHA-256 wrapper. Kept as a tiny helper so the rest of
    /// the file stays focused on the backup/restore flow. CommonCrypto is
    /// always available on macOS so no extra module map is required.
    private static func sha256CC(_ data: Data) -> [UInt8] {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash
    }
}

/// Errors surfaced by `BackupManager` to the restore flow.
public enum BackupError: Error {
    /// `manifest.json` could not be read from the backup directory.
    /// `path` is the URL of the missing manifest.
    case missingManifest(path: String)
    /// `manifest.json` was readable but could not be decoded as a
    /// `Manifest`. `underlying` is the JSON decode error.
    case corruptManifest(path: String, underlying: Error)
}