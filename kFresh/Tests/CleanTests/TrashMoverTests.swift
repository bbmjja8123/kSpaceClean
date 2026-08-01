import XCTest
@testable import kFresh

final class TrashMoverTests: XCTestCase {
    func testCanMoveUserAppReturnsTrue() {
        let app = makeApp(bundleID: "com.example.user", path: "/Applications/UserApp.app", isProtected: false)
        XCTAssertTrue(TrashMover.canMoveToTrash(app: app))
    }

    func testCanMoveProtectedAppReturnsFalse() {
        let app = makeApp(bundleID: "com.apple.finder", path: "/System/Library/Finder.app", isProtected: true)
        XCTAssertFalse(TrashMover.canMoveToTrash(app: app))
    }

    func testMoveToTrashReturnsProtectedErrorForProtectedApp() async {
        let app = makeApp(bundleID: "com.apple.finder", path: "/System/Library/Finder.app", isProtected: true)
        let mover = TrashMover(auditLogger: nil, historyRepo: UninstallHistoryRepository(inMemory: true))
        let result = await mover.moveToTrash(app: app, residues: [])
        switch result {
        case .failure(.protected(let reason)):
            XCTAssertFalse(reason.isEmpty)
        default:
            XCTFail("Expected .protected failure, got \(result)")
        }
    }

    func testMoveToTrashWritesAuditEventOnSuccess() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let auditURL = tempDir.appendingPathComponent("audit.jsonl")
        let logger = try AuditLogger(logURL: auditURL)
        let mover = TrashMover(auditLogger: logger, historyRepo: UninstallHistoryRepository(inMemory: true))

        let app = makeApp(bundleID: "com.example.test", path: "/tmp/Test-\(UUID().uuidString).app", isProtected: false)
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: app.url.path), withIntermediateDirectories: true)

        let result = await mover.moveToTrash(app: app, residues: [])

        guard case .success(let record) = result else {
            XCTFail("Expected .success, got \(result)")
            return
        }
        XCTAssertEqual(record.bundleID, "com.example.test")

        let events = await logger.recentEvents(limit: 10)
        XCTAssertGreaterThan(events.count, 0)
        XCTAssertEqual(events.first?.bundleID, "com.example.test")
        XCTAssertEqual(events.first?.status, "success")
    }

    func testRestoreRefusesToOverwriteWhenOriginalPathOccupied() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let originalPath = tempDir.appendingPathComponent("Original.app")
        try FileManager.default.createDirectory(at: originalPath, withIntermediateDirectories: true)
        let sentinel = originalPath.appendingPathComponent("sentinel.txt")
        try "original".write(to: sentinel, atomically: true, encoding: .utf8)

        let record = UninstallRecord(
            id: UUID(),
            appName: "Original",
            bundleID: "com.example.test",
            appPath: originalPath.path,
            actualTrashPath: tempDir.appendingPathComponent("does-not-exist.app").path,
            appSize: 0,
            totalResidueSize: 0,
            residueCount: 0,
            uninstalledAt: Date(),
            isRestored: false,
            backupPath: "",
            residues: []
        )

        let mover = TrashMover(auditLogger: nil, historyRepo: UninstallHistoryRepository(inMemory: true))
        let result = await mover.restore(record: record)

        guard case .failure(.restoreRefusedOverwrite(let refusedPath)) = result else {
            XCTFail("Expected .restoreRefusedOverwrite failure, got \(result)")
            return
        }
        XCTAssertEqual(refusedPath, originalPath.path)

        // Restore must NEVER overwrite, regardless of result variant.
        let content = try String(contentsOf: sentinel)
        XCTAssertEqual(content, "original", "Existing sentinel must remain untouched")
    }

    /// Covers I2 + I2b: residue counts, sizes, and paths in the record reflect
    /// ONLY the residues that were actually deleted — not the input set, not
    /// the filtered set, and not failures. Per-residue failures are still
    /// reported via the audit event so the operator can investigate.
    func testMoveToTrashFiltersAndReportsResidueFailures() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let auditURL = tempDir.appendingPathComponent("audit.jsonl")
        let logger = try AuditLogger(logURL: auditURL)
        let mover = TrashMover(auditLogger: logger, historyRepo: UninstallHistoryRepository(inMemory: true))

        // App to uninstall
        let appPath = tempDir.appendingPathComponent("Multi-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: appPath, withIntermediateDirectories: true)

        // One residue that DOES exist and WILL be deleted (filtered)
        let okResidue = tempDir.appendingPathComponent("ok.plist")
        try "ok".write(to: okResidue, atomically: true, encoding: .utf8)
        // One residue that DOES NOT exist (filtered) — removeItem will throw
        let missingResidue = tempDir.appendingPathComponent("missing.plist")
        // One residue that is BELOW the confidence threshold — must be skipped
        let lowConfidenceResidue = tempDir.appendingPathComponent("low.plist")
        try "low".write(to: lowConfidenceResidue, atomically: true, encoding: .utf8)

        let app = InstalledApp(
            url: appPath,
            displayName: "Multi",
            bundleID: "com.example.multi",
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 0,
            source: .userInstalled,
            isRunning: false,
            lastUsedDate: nil,
            residues: []
        )
        let residues = [
            ResidueFile(url: okResidue, type: .preferences, sizeBytes: 2, confidence: 0.9, description: "will delete"),
            ResidueFile(url: missingResidue, type: .caches, sizeBytes: 100, confidence: 0.9, description: "will fail"),
            ResidueFile(url: lowConfidenceResidue, type: .other, sizeBytes: 3, confidence: 0.3, description: "below threshold"),
        ]

        let result = await mover.moveToTrash(app: app, residues: residues)
        guard case .success(let record) = result else {
            XCTFail("Expected .success, got \(result)")
            return
        }
        // I2b: counts must reflect ONLY actually-deleted residues (ok only),
        // not the filtered set (ok + missing = 2) and not the input set (3).
        XCTAssertEqual(record.residueCount, 1, "residueCount must reflect only successfully deleted residues")
        XCTAssertEqual(record.totalResidueSize, 2, "totalResidueSize must reflect only successfully deleted residues")
        XCTAssertEqual(Set(record.residues.map(\.url.path)), Set([okResidue.path]),
                       "record.residues must contain only the successfully deleted path")

        let events = await logger.recentEvents(limit: 10)
        let trashEvent = events.first { $0.action == "trash" && $0.bundleID == "com.example.multi" }
        XCTAssertNotNil(trashEvent)
        XCTAssertEqual(trashEvent?.status, "success")
        XCTAssertNotNil(trashEvent?.errorMessage,
                        "Residue failure must be reported in the success event's errorMessage")
        XCTAssertTrue(trashEvent?.errorMessage?.contains("missing.plist") ?? false,
                      "Audit must name the specific residue that failed")
        XCTAssertFalse(trashEvent?.paths.contains(lowConfidenceResidue.path) ?? true,
                       "Audit paths must exclude residues filtered out by confidence")

        // Cleanup side-effect: okResidue deleted, lowConfidenceResidue untouched
        XCTAssertFalse(FileManager.default.fileExists(atPath: okResidue.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lowConfidenceResidue.path),
                      "Below-confidence residue must not be deleted")
    }

    /// Covers C1: restore refuses with .trashedItemMissing when the actual
    /// trashed item is gone (Trash emptied), without destroying the backup
    /// or marking the record restored.
    func testRestoreRefusesWithTrashedItemMissingWhenItemGone() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let originalPath = tempDir.appendingPathComponent("App.app")
        // Create the backup directory + sentinel so we can prove the
        // backup survives the failed restore (no cleanup call ran).
        let backupPath = tempDir.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: backupPath, withIntermediateDirectories: true)
        let backupSentinel = backupPath.appendingPathComponent("residue.plist")
        try "user-data".write(to: backupSentinel, atomically: true, encoding: .utf8)

        let record = UninstallRecord(
            id: UUID(),
            appName: "App",
            bundleID: "com.example.emptied",
            appPath: originalPath.path,
            actualTrashPath: tempDir.appendingPathComponent("App-emptied.app").path,
            appSize: 0,
            totalResidueSize: 0,
            residueCount: 0,
            uninstalledAt: Date(),
            isRestored: false,
            backupPath: backupPath.path,
            residues: []
        )

        let mover = TrashMover(auditLogger: nil, historyRepo: UninstallHistoryRepository(inMemory: true))
        let result = await mover.restore(record: record)

        guard case .failure(.trashedItemMissing(let bundleID)) = result else {
            XCTFail("Expected .trashedItemMissing failure, got \(result)")
            return
        }
        XCTAssertEqual(bundleID, "com.example.emptied")
        // Original path should NOT have been created (no silent bootstrap).
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalPath.path),
                       "Restore must not create the original path when the trashed item is missing")
        // Backup sentinel must still be on disk — no cleanup ran.
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupSentinel.path),
                      "Backup must be preserved when restore refuses on missing trashed item")
        // No history record was marked restored.
        let records = await mover.recentRecords(limit: 10)
        XCTAssertTrue(records.allSatisfy { $0.isRestored == false },
                      "No record must be marked restored when the restore refuses on missing trashed item")
    }

    /// Covers C1b: when the residue-restore step throws, `TrashMover.restore`
    /// must return `.failure(.restoreResidueFailed)` and MUST NOT call
    /// `markRestored` or `cleanup` — otherwise the only copy of the
    /// user's residue data is silently destroyed. We force a real
    /// `BackupManager.restore` failure by pointing the residue's original
    /// path at a non-existent parent directory: the backup file exists
    /// (so the `fileExists` guard passes), but `copyItem` throws because
    /// the destination directory is missing.
    func testRestorePreservesBackupWhenResidueRestoreFails() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let auditURL = tempDir.appendingPathComponent("audit.jsonl")
        let logger = try AuditLogger(logURL: auditURL)

        // Seed a real `UninstallRecord` into an in-memory history repo so the
        // post-restore assertion can verify `isRestored` is still `false`.
        // A fresh empty repository would make `recentRecords.allSatisfy
        // { !$0.isRestored }` vacuously true — the assertion proves nothing
        // because `recentRecords` is empty whether `markRestored` was
        // correctly skipped or incorrectly called.
        // I3b fix: use the injected repo + `seedHistoryRecord`.
        let seededRepo = UninstallHistoryRepository(inMemory: true)
        let mover = TrashMover(auditLogger: logger, historyRepo: seededRepo)

        // Real backup dir + sentinel that must survive a failed restore.
        let backupPath = tempDir.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: backupPath, withIntermediateDirectories: true)
        let residueName = "preferences.plist"
        let sentinel = backupPath.appendingPathComponent(residueName)
        try "user-data".write(to: sentinel, atomically: true, encoding: .utf8)
        let manifest = BackupManager.Manifest(
            bundleID: "com.example.c1b",
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
        try manifestData.write(to: backupPath.appendingPathComponent("manifest.json"))

        // Real "trashed" app that moveItem can pick up.
        let trashedApp = tempDir.appendingPathComponent("Trashed.app")
        try FileManager.default.createDirectory(at: trashedApp, withIntermediateDirectories: true)

        // Residue record: the URL's parent directory is deliberately NOT
        // created, so copyItem from the backup to the original location
        // throws NSCocoaErrorDomain Code=512 ("no such file").
        let missingParent = tempDir.appendingPathComponent("nonexistent-parent")
        let missingResidue = missingParent.appendingPathComponent(residueName)

        let seededID = UUID()
        let record = UninstallRecord(
            id: seededID,
            appName: "Trashed",
            bundleID: "com.example.c1b",
            appPath: tempDir.appendingPathComponent("Original.app").path,
            actualTrashPath: trashedApp.path,
            appSize: 0,
            totalResidueSize: 9,
            residueCount: 1,
            uninstalledAt: Date(),
            isRestored: false,
            backupPath: backupPath.path,
            residues: [
                ResidueFile(url: missingResidue, type: .preferences, sizeBytes: 9, confidence: 0.9, description: "dest-dir-missing")
            ]
        )
        await mover.seedHistoryRecord(record)

        let result = await mover.restore(record: record)

        guard case .failure(.restoreResidueFailed(let underlying)) = result else {
            XCTFail("Expected .failure(.restoreResidueFailed), got \(result)")
            return
        }
        XCTAssertNotNil(underlying as NSError, "Underlying error must be propagated, not swallowed")

        // The sentinel MUST still be on disk — `cleanup` must not have run.
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path),
                      "Backup sentinel must survive a failed residue restore (no cleanup call)")

        // I3b fix: the seeded record must still be retrievable AND its
        // `isRestored` flag must still be `false`. A vacuous allSatisfy on
        // an empty array would have passed even if `markRestored` flipped a
        // record we never seeded — this assertion cannot.
        let stored = await mover.historyRecord(id: seededID)
        XCTAssertNotNil(stored, "Seeded record must still be retrievable from history")
        XCTAssertEqual(stored?.id, seededID, "Stored record id must match seeded id")
        XCTAssertFalse(stored?.isRestored ?? true,
                       "Seeded record's isRestored MUST remain false after a failed residue restore (markRestored must not have been called)")

        // Audit log records the residue-restore failure (recoverable, distinct
        // from `trashFailed`) so the operator can correlate the half-restored
        // state with the right event.
        let events = await logger.recentEvents(limit: 10)
        let failureEvent = events.first { $0.action == "restore" && $0.status == "failure" }
        XCTAssertNotNil(failureEvent, "Audit must record the residue-restore failure")
        XCTAssertTrue(failureEvent?.errorMessage?.contains("backup preserved") ?? false,
                      "Audit errorMessage must signal that the backup was preserved, not destroyed")
    }

    // Covers Codable backwards-compat: an `UninstallRecord` JSON that was
    // persisted before the `actualTrashPath` field existed must decode
    // cleanly. A synthesised `init(from:)` would throw on the missing key;
    // the custom decoder must treat it as `""` (the legacy default).
    func testUninstallRecordDecodesLegacyRecordWithoutActualTrashPath() throws {
        let legacyJSON = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "appName": "LegacyApp",
            "bundleID": "com.example.legacy",
            "appPath": "/Applications/LegacyApp.app",
            "appSize": 4096,
            "totalResidueSize": 1024,
            "residueCount": 1,
            "uninstalledAt": "2026-01-01T00:00:00Z",
            "isRestored": false,
            "backupPath": "/tmp/backup",
            "residues": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(UninstallRecord.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(record.id.uuidString, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(record.appName, "LegacyApp")
        XCTAssertEqual(record.bundleID, "com.example.legacy")
        XCTAssertEqual(record.appPath, "/Applications/LegacyApp.app")
        XCTAssertEqual(record.actualTrashPath, "",
                       "Missing actualTrashPath must decode to empty string, not throw")
        XCTAssertEqual(record.appSize, 4096)
        XCTAssertEqual(record.totalResidueSize, 1024)
        XCTAssertEqual(record.residueCount, 1)
        XCTAssertFalse(record.isRestored)
        XCTAssertEqual(record.backupPath, "/tmp/backup")
    }

    // MARK: - Helpers

    private func makeApp(bundleID: String, path: String, isProtected: Bool) -> InstalledApp {
        InstalledApp(
            url: URL(fileURLWithPath: path),
            displayName: "Test",
            bundleID: bundleID,
            version: "1.0",
            source: isProtected ? .system : .userInstalled,
            isRunning: false,
            lastUsedDate: nil
        )
    }
}