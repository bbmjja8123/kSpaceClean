import XCTest
@testable import kUninstall

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

    func testCleanupExpired() {
        let manager = BackupManager()
        // Should not throw for non-existent backup
        manager.cleanupExpired(olderThan: 1)
    }
}
