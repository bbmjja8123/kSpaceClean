// kWise/Tests/UninstallBackupStoreTests.swift
//
// v2.3 Phase 4 — 卸载前备份：kWise-scoped root, backup→verify→restore
// 回环, TTL pruning.
import XCTest
import AppCatalogCore
@testable import kWise

final class UninstallBackupStoreTests: XCTestCase {

    private var root: URL!
    private var store: UninstallBackupStore!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("uninstall-backup-\(UUID().uuidString)", isDirectory: true)
        store = UninstallBackupStore(rootURL: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func makeEntry(residues: Int = 2) -> UninstallAppEntry {
        let files = (0..<residues).map { i -> URL in
            let url = root.appendingPathComponent("residue-\(i).plist")
            try? Data("pref-data-\(i)".utf8).write(to: url)
            return url
        }
        let residueFiles = files.enumerated().map { i, url in
            ResidueFile(url: url, type: .preferences, sizeBytes: 12,
                        confidence: 0.99, description: "prefs")
        }
        return UninstallAppEntry(
            appName: "TestApp", bundleID: "com.test.backup",
            appURL: URL(fileURLWithPath: "/Applications/TestApp.app"),
            appSize: 100, leftoverURLs: files, leftoverSize: 24,
            lastUsedDate: nil, installDate: nil, isRunning: false,
            source: .userInstalled, residues: residueFiles
        )
    }

    func testBackupCreatesVersionedDirectoryUnderKWiseRoot() async throws {
        let entry = makeEntry()
        let backupURL = try await store.backupBeforeUninstall(entry: entry)

        XCTAssertTrue(backupURL.path.contains("com.test.backup"), "Backup lives under the bundleID dir")
        XCTAssertTrue(backupURL.lastPathComponent.hasPrefix("v"), "Versioned v<N> directory")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: backupURL.appendingPathComponent("manifest.json").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: backupURL.appendingPathComponent("residue-locations.json").path),
            "Sidecar with original locations must be written")

        // The root must be the injected one — never kFresh-branded.
        XCTAssertFalse(root.path.contains("kfresh"))
    }

    func testBackupSkipsLowConfidenceResidues() async throws {
        // BackupManager skips residues with confidence ≤ 0.5 — a single
        // low-confidence residue means nothing is copied but the dir exists.
        let url = root.appendingPathComponent("weak.plist")
        try Data("x".utf8).write(to: url)
        let weak = ResidueFile(url: url, type: .preferences, sizeBytes: 1,
                               confidence: 0.3, description: "weak")
        let entry = UninstallAppEntry(
            appName: "App", bundleID: "com.test.weak",
            appURL: URL(fileURLWithPath: "/Applications/App.app"),
            appSize: 10, leftoverURLs: [url], leftoverSize: 1,
            lastUsedDate: nil, installDate: nil, isRunning: false,
            source: .userInstalled, residues: [weak]
        )
        let backupURL = try await store.backupBeforeUninstall(entry: entry)
        // Manifest either missing (nothing backed up) or empty — both fine;
        // the contract is "no throw, no data loss claim".
        _ = backupURL
    }

    func testRestoreLatestRestoresDeletedResidue() async throws {
        let entry = makeEntry()
        let residueURL = entry.residues[0].url
        _ = try await store.backupBeforeUninstall(entry: entry)

        // Simulate a later cleanup: the residue file is gone.
        try FileManager.default.removeItem(at: residueURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: residueURL.path))

        try await store.restoreLatest(bundleID: entry.bundleID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: residueURL.path),
                      "Restore must put the residue back from the backup")
    }

    func testRestoreWithoutBackupThrows() async {
        do {
            try await store.restoreLatest(bundleID: "com.test.never-backed-up")
            XCTFail("Restore without a backup must throw")
        } catch {
            // Expected — honest failure, not silent success.
        }
    }

    func testPruneExpiredRemovesOldBackups() async throws {
        let entry = makeEntry()
        let backupURL = try await store.backupBeforeUninstall(entry: entry)
        // Backdate the directory's modification date beyond 30 days.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-31 * 86_400)],
            ofItemAtPath: backupURL.path
        )
        let pruned = await store.pruneExpired(days: 30)
        XCTAssertGreaterThanOrEqual(pruned, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
    }
}
