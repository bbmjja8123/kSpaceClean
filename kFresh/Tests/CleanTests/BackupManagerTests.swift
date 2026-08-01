import XCTest
@testable import kFresh

/// Tests for the versioned ``BackupManager`` rewrite.
///
/// Layout under test:
///   `<rootURL>/<bundleID>/v<N>/manifest.json` + backed-up files
///
/// Where the pre-rewrite actor stored all versions in a single flat
/// directory, the rewrite gives each backup its own versioned subdirectory
/// and writes a `manifest.json` describing the contents + sha256 of every
/// file. `verify` re-reads the manifest and re-hashes every file to detect
/// silent corruption between `backup` and `restore`.
///
/// The I3d preservation test (the last one in this file) is the
/// load-bearing safety guard: it asserts that when `restore` is asked to
/// copy a backup over an existing destination but the copy fails, the
/// existing file is still on disk after the failed restore. The
/// pre-rewrite actor used temp-and-rename; this rewrite keeps that
/// property, just inside the new versioned directory layout.
final class BackupManagerTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        do {
            try FileManager.default.removeItem(at: tempDir)
        } catch {
            // best-effort teardown — do not fail the test on cleanup errors
            print("BackupManagerTests: failed to remove tempDir \(tempDir.path): \(error)")
        }
    }

    // MARK: - Brief test 1: backup creates a versioned directory + manifest

    /// `backup` creates `v<N>/` under the bundleID directory and writes a
    /// `manifest.json` containing the bundleID. The version is derived
    /// from the number of pre-existing versioned directories.
    func testBackupCreatesVersionedDirectory() async throws {
        let sourceFile = tempDir.appendingPathComponent("source.plist")
        try Data("test".utf8).write(to: sourceFile)

        let residue = ResidueFile(url: sourceFile, type: .preferences, sizeBytes: 4, confidence: 0.9, description: "test", isSystemLevel: false, isProtected: false)
        let manager = BackupManager(rootURL: tempDir.appendingPathComponent("backups"))

        let backupURL = try await manager.backup(residues: [residue], bundleID: "com.example.test")

        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        let manifest = try String(contentsOf: backupURL.appendingPathComponent("manifest.json"))
        XCTAssertTrue(manifest.contains("com.example.test"))
    }

    // MARK: - Brief test 2: restore does not overwrite a more-recent file

    /// If the residue file at `originalResidues[i].url` has been modified
    /// AFTER the backup was taken, restore must NOT clobber it. The
    /// pre-rewrite behaviour was to copy over the residue unconditionally;
    /// the rewrite skips entries whose current size is `>=` the backup's
    /// recorded size, treating that as a heuristic for "newer or equal".
    func testRestoreDoesNotOverwriteExistingFile() async throws {
        let sourceFile = tempDir.appendingPathComponent("source.plist")
        try Data("original".utf8).write(to: sourceFile)

        let residue = ResidueFile(url: sourceFile, type: .preferences, sizeBytes: 8, confidence: 0.9, description: "test", isSystemLevel: false, isProtected: false)
        let manager = BackupManager(rootURL: tempDir.appendingPathComponent("backups"))
        _ = try await manager.backup(residues: [residue], bundleID: "com.example.test")

        // Modify source — current contents are now "modified" (8 bytes).
        try Data("modified".utf8).write(to: sourceFile)

        // Restore must NOT overwrite: the test's residue.sizeBytes == 8,
        // the file on disk is also 8 bytes, so the existing file is treated
        // as "at least as new" and restore skips it.
        try await manager.restore(
            backupPath: tempDir.appendingPathComponent("backups/com.example.test/v1"),
            originalResidues: [residue]
        )

        let current = try String(contentsOf: sourceFile)
        XCTAssertEqual(current, "modified", "Restore must not overwrite more recent file")
    }

    // MARK: - Brief test 3: cleanupExpired removes old bundle directories

    /// `cleanupExpired(olderThanDays:)` walks the top-level root and removes
    /// any bundleID directory whose creationDate is older than the cutoff.
    /// The versioned subdirectories (`v<N>/`) move with the parent, so
    /// removing the bundle directory is sufficient.
    func testCleanupExpiredRemovesOldBackups() async throws {
        let backupRoot = tempDir.appendingPathComponent("backups")
        let oldBundle = backupRoot.appendingPathComponent("com.example.old")
        try FileManager.default.createDirectory(at: oldBundle, withIntermediateDirectories: true)
        let oldDate = Date().addingTimeInterval(-40 * 86400)
        try FileManager.default.setAttributes([.creationDate: oldDate], ofItemAtPath: oldBundle.path)

        let manager = BackupManager(rootURL: backupRoot)
        let removed = await manager.cleanupExpired(olderThanDays: 30)

        XCTAssertGreaterThanOrEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldBundle.path))
    }

    // MARK: - Brief test 4: verify returns true for an intact backup

    /// `verify` reads the manifest, re-hashes every file, and compares
    /// against the recorded sha256. A backup that round-tripped through
    /// `backup` should pass verification because the hashes were computed
    /// at backup time.
    func testVerifyReturnsTrueForIntactBackup() async throws {
        let sourceFile = tempDir.appendingPathComponent("source.plist")
        try Data("test".utf8).write(to: sourceFile)
        let residue = ResidueFile(url: sourceFile, type: .preferences, sizeBytes: 4, confidence: 0.9, description: "test", isSystemLevel: false, isProtected: false)
        let manager = BackupManager(rootURL: tempDir.appendingPathComponent("backups"))
        let backupURL = try await manager.backup(residues: [residue], bundleID: "com.example.test")

        let valid = try await manager.verify(backupPath: backupURL)
        XCTAssertTrue(valid)
    }

    /// `verify` must reject a backup whose on-disk contents no longer match
    /// the SHA-256 recorded in its manifest.
    func testVerifyReturnsFalseWhenFileCorrupted() async throws {
        let sourceFile = tempDir.appendingPathComponent("source.plist")
        try Data("test".utf8).write(to: sourceFile)
        let residue = ResidueFile(url: sourceFile, type: .preferences, sizeBytes: 4, confidence: 0.9, description: "test", isSystemLevel: false, isProtected: false)
        let manager = BackupManager(rootURL: tempDir.appendingPathComponent("backups"))
        let backupURL = try await manager.backup(residues: [residue], bundleID: "com.example.test")
        try Data("test!".utf8).write(to: backupURL.appendingPathComponent("source.plist"))

        let valid = try await manager.verify(backupPath: backupURL)
        XCTAssertFalse(valid)
    }

    // MARK: - I6 missing-backup-file guard

    /// `BackupManager.restore` must throw `BackupError.missingBackupFile`
    /// when the manifest references a file that no longer exists in the
    /// backup directory. Previously the loop silently `continue`d, the
    /// manifest claimed a successful restore, and `TrashMover.cleanup`
    /// would then delete the entire backup directory — leaving the user
    /// with a "successful restore" that restored nothing.
    ///
    /// The fix: throw `BackupError.missingBackupFile(path:)` so the caller
    /// (TrashMover) sees the same error model as `missingManifest` /
    /// `corruptManifest` and preserves the backup directory for retry.
    func testRestoreThrowsWhenManifestReferencesMissingFile() async throws {
        let manager = BackupManager(rootURL: tempDir.appendingPathComponent("backups"))

        // Set up a valid destination file (the residue to be restored).
        let residueName = "will-be-missing.plist"
        let destination = tempDir.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let destinationFile = destination.appendingPathComponent(residueName)
        try "current-state".write(to: destinationFile, atomically: true, encoding: .utf8)

        // Set up a backup directory with manifest but NO actual backup file.
        let backupRoot = tempDir.appendingPathComponent("backups/com.example.missing/v1")
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        // Note: backupFile is deliberately NOT created.

        let manifest = BackupManager.Manifest(
            bundleID: "com.example.missing",
            createdAt: Date(),
            version: 1,
            files: [
                BackupManager.Manifest.ManifestEntry(
                    relativePath: residueName,
                    sizeBytes: 9,
                    sha256: BackupManager.sha256HexForTest(Data("original".utf8))
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: backupRoot.appendingPathComponent("manifest.json"))

        let residue = ResidueFile(
            url: destinationFile,
            type: .preferences,
            sizeBytes: 9,
            confidence: 0.9,
            description: "restored-target",
            isSystemLevel: false,
            isProtected: false
        )

        do {
            try await manager.restore(backupPath: backupRoot, originalResidues: [residue])
            XCTFail("Expected BackupError.missingBackupFile to be thrown")
        } catch let error as BackupError {
            switch error {
            case .missingBackupFile(let path):
                XCTAssertTrue(path.hasSuffix(residueName),
                              "Error path should point at the missing backup file: \(path)")
            default:
                XCTFail("Expected BackupError.missingBackupFile, got \(error)")
            }
        }
    }

    // MARK: - I3d preservation guard

    /// When `BackupManager.restore` is asked to copy a backup over an
    /// existing destination file but the copy fails, the existing file
    /// MUST still be on disk after the failed restore. Pre-fix behaviour:
    /// `removeItem` on the destination first, then `copyItem`. If
    /// `copyItem` threw, the user lost their existing residue AND did not
    /// get the restored copy. Post-fix behaviour: temp-and-rename; the
    /// existing destination is untouched until the copy is verified.
    ///
    /// We force the copy to fail by chmod-ing the backup file to `000`
    /// AFTER the manager's pre-flight `fileExists` check. `fileExists`
    /// uses `stat(2)` which succeeds on any existing file regardless of
    /// permissions, but `copyItem` opens the source for reading and throws
    /// EACCES. The restore must propagate the error AND leave the
    /// existing destination byte-identical to its pre-restore state.
    ///
    /// This is the load-bearing safety guard from the I3d fix in the
    /// interim `BackupManager`. The versioned rewrite preserves the
    /// guarantee; this test guards against regression.
    func testRestorePreservesExistingFileWhenCopyFails() async throws {
        let manager = BackupManager(rootURL: tempDir.appendingPathComponent("backups"))

        // Set up a destination file that already exists with known
        // contents — this is the file the user currently has on disk that
        // a failed restore MUST NOT destroy. Keep it small (1 byte) so the
        // restore heuristic `existingSize >= entry.sizeBytes` does NOT
        // skip the copy: the backup file we set up below is 9 bytes, so
        // the restore must actually attempt the copy and hit EACCES on
        // the chmod 000 backup source.
        let residueName = "preferences.plist"
        let destination = tempDir.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let existingFile = destination.appendingPathComponent(residueName)
        let existingContents = "x"
        try existingContents.write(to: existingFile, atomically: true, encoding: .utf8)
        // Readable perms so the post-restore assertion can read it.
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o644)],
                                              ofItemAtPath: existingFile.path)

        // Set up a backup directory + an unreadable backup file. `fileExists`
        // still returns true (stat succeeds on 000-mode files) but `copyItem`
        // throws EACCES when it tries to open the source for reading.
        let backupRoot = tempDir.appendingPathComponent("backups/com.example.i3d/v1")
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        let backupFile = backupRoot.appendingPathComponent(residueName)
        try "user-data".write(to: backupFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o000)],
                                              ofItemAtPath: backupFile.path)

        // A valid manifest ensures this test enters the restore copy loop;
        // without it, restore would fail earlier while reading the manifest.
        let manifest = BackupManager.Manifest(
            bundleID: "com.example.i3d",
            createdAt: Date(),
            version: 1,
            files: [
                BackupManager.Manifest.ManifestEntry(
                    relativePath: residueName,
                    sizeBytes: 9,
                    sha256: BackupManager.sha256HexForTest(Data("user-data".utf8))
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: backupRoot.appendingPathComponent("manifest.json"))

        let residue = ResidueFile(
            url: existingFile,
            type: .preferences,
            sizeBytes: 9,
            confidence: 0.9,
            description: "destination-occupied",
            isSystemLevel: false,
            isProtected: false
        )

        do {
            try await manager.restore(backupPath: backupRoot, originalResidues: [residue])
            XCTFail("Expected restore to throw because the backup source is unreadable")
        } catch let error as BackupError {
            XCTFail("Expected copy to fail with NSError, got BackupError: \(error)")
        } catch {
            // Expected: copy failed with EACCES on chmod-000 source. Underlying
            // error is whatever FileManager.copyItem raised.
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: existingFile.path),
                      "Existing destination must survive a failed restore (no pre-delete)")
        let preserved = try String(contentsOf: existingFile, encoding: .utf8)
        XCTAssertEqual(preserved, existingContents,
                       "Existing destination contents must be byte-identical after a failed restore")
    }
}