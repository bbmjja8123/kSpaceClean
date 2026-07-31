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

        _ = await mover.moveToTrash(app: app, residues: [])

        let events = await logger.recentEvents(limit: 10)
        XCTAssertGreaterThan(events.count, 0)
        XCTAssertEqual(events.first?.bundleID, "com.example.test")
    }

    func testRestoreDoesNotOverwriteExistingFile() async throws {
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

        // Restore should refuse to overwrite
        if case .success = result {
            let content = try String(contentsOf: sentinel)
            XCTAssertEqual(content, "original", "Existing file must not be overwritten")
        }
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