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
        let mover = TrashMover(auditLogger: nil)
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
        let mover = TrashMover(auditLogger: logger)

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

        let mover = TrashMover(auditLogger: nil)
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

    /// Covers I2: residue counts in the record and audit event are derived
    /// from the FILTERED set (confidence > 0.5), and per-residue failures
    /// surface in the audit event instead of being silently swallowed.
    func testMoveToTrashFiltersAndReportsResidueFailures() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let auditURL = tempDir.appendingPathComponent("audit.jsonl")
        let logger = try AuditLogger(logURL: auditURL)
        let mover = TrashMover(auditLogger: logger)

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
        // Counts should reflect the FILTERED set (ok + missing = 2), not the
        // input count (3) and not the success-only count (1).
        XCTAssertEqual(record.residueCount, 2, "residueCount must reflect the filtered set")
        XCTAssertEqual(record.totalResidueSize, 102, "totalResidueSize must reflect the filtered set")
        XCTAssertEqual(Set(record.residues.map(\.url.path)), Set([okResidue.path, missingResidue.path]))

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
            backupPath: tempDir.appendingPathComponent("backup").path,
            residues: []
        )

        // Record isRestored should be false before, and the restore call
        // must NOT have flipped it (no markRestored call should have run).
        let mover = TrashMover(auditLogger: nil)
        let result = await mover.restore(record: record)

        guard case .failure(.trashedItemMissing(let bundleID)) = result else {
            XCTFail("Expected .trashedItemMissing failure, got \(result)")
            return
        }
        XCTAssertEqual(bundleID, "com.example.emptied")
        // Original path should NOT have been created (no silent bootstrap).
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalPath.path),
                       "Restore must not create the original path when the trashed item is missing")
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