import XCTest
@testable import kFresh

final class BackupManagerTests: XCTestCase {
    func testBackupAndRestoreRoundTrip() async throws {
        let manager = BackupManager()

        // Create a temporary residue for testing
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("com.example.test.backup")
        try "test data".write(to: testFile, atomically: true, encoding: .utf8)

        let residue = ResidueFile(
            url: testFile,
            type: .preferences,
            sizeBytes: 9,
            confidence: 1.0,
            description: "Test residue"
        )

        // Backup
        let backupPath = try await manager.backup(residues: [residue], bundleID: "com.example.test")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupPath.path))
        XCTAssertTrue(backupPath.lastPathComponent.hasPrefix("com.example.test"))

        // Restore
        try await manager.restore(backupPath: backupPath, originalResidues: [residue])
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path))

        // Cleanup
        try? FileManager.default.removeItem(at: testFile)
        try? FileManager.default.removeItem(at: backupPath.deletingLastPathComponent())
    }

    func testCleanupExpired() async {
        let manager = BackupManager()
        // Should not throw for non-existent backup
        await manager.cleanupExpired(olderThan: 1)
    }

    /// I3d: when `BackupManager.restore` is asked to copy a backup over an
    /// existing file but the copy fails, the existing file MUST still be
    /// on disk after the failed restore. Pre-fix behaviour: `removeItem`
    /// on the destination first, then `copyItem`. If `copyItem` threw
    /// (e.g. backup file unreadable mid-flight), the user lost their
    /// existing residue AND did not get the restored copy. Post-fix
    /// behaviour: temp-and-rename; the existing destination is untouched
    /// until the copy is verified.
    ///
    /// We force the copy to fail by making the backup file unreadable
    /// AFTER the manager's pre-flight `fileExists` check would pass. We
    /// chmod the backup file to `000` so `copyItem` (which opens the
    /// source for reading) throws EACCES. The pre-flight `fileExists`
    /// uses `stat(2)` which succeeds on any existing file regardless of
    /// permissions, so the `if fileManager.fileExists(atPath: backupFile.path)`
    /// guard passes and the copy is actually attempted.
    func testRestorePreservesExistingFileWhenCopyFails() async throws {
        let manager = BackupManager()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.example.restore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let residueName = "preferences.plist"

        // Backup file: an unreadable file so `copyItem` throws EACCES.
        // `fileExists` still returns true (stat succeeds on 000-mode files),
        // so the manager's pre-flight guard passes and the copy is attempted.
        let backupDir = tempDir.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let backupFile = backupDir.appendingPathComponent(residueName)
        try "user-data".write(to: backupFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o000)],
                                                ofItemAtPath: backupFile.path)

        // Pre-existing destination file that must survive the failed restore.
        let existingDestination = tempDir.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: existingDestination, withIntermediateDirectories: true)
        let existingFile = existingDestination.appendingPathComponent(residueName)
        let existingContents = "original-data-untouched"
        try existingContents.write(to: existingFile, atomically: true, encoding: .utf8)
        // Restore readable perms so the assertion read works.
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o644)],
                                                ofItemAtPath: existingFile.path)

        let residue = ResidueFile(
            url: existingFile,
            type: .preferences,
            sizeBytes: 9,
            confidence: 1.0,
            description: "destination-occupied"
        )

        do {
            try await manager.restore(backupPath: backupDir, originalResidues: [residue])
            XCTFail("Expected restore to throw because the backup source is unreadable")
        } catch {
            // Expected: the copy failed because the source is unreadable
            // (EACCES). The exact error code is irrelevant — what matters
            // is that the existing destination file is still on disk.
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: existingFile.path),
                      "Existing destination must survive a failed restore (no pre-delete)")
        let preserved = try String(contentsOf: existingFile, encoding: .utf8)
        XCTAssertEqual(preserved, existingContents,
                       "Existing destination contents must be byte-identical after a failed restore")
    }
}
