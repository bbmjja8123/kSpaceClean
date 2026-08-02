import XCTest
@testable import kFresh

/// Coverage for `DeepCleanEngine` — the Pro deep-clean scanner/deleter.
///
/// The engine's three directory URLs are injectable, so every test points
/// them at temporary fixtures and never touches the real
/// `/Library/LaunchAgents`, `/Library/LaunchDaemons`, or
/// `/Library/PreferencePanes`.
final class DeepCleanEngineTests: XCTestCase {

    private var tempDir: URL!
    private var launchAgentsDir: URL!
    private var launchDaemonsDir: URL!
    private var prefPanesDir: URL!
    private var backupRoot: URL!
    private var auditLogURL: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        launchAgentsDir = tempDir.appendingPathComponent("LaunchAgents")
        launchDaemonsDir = tempDir.appendingPathComponent("LaunchDaemons")
        prefPanesDir = tempDir.appendingPathComponent("PreferencePanes")
        backupRoot = tempDir.appendingPathComponent("backups")
        auditLogURL = tempDir.appendingPathComponent("audit/deepclean.jsonl")
        for dir in [launchAgentsDir!, launchDaemonsDir!, prefPanesDir!] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    override func tearDown() async throws {
        do {
            try FileManager.default.removeItem(at: tempDir)
        } catch {
            // Best-effort teardown — never fail a test on cleanup errors.
            print("DeepCleanEngineTests: failed to remove tempDir \(tempDir.path): \(error)")
        }
    }

    // MARK: - Fixtures

    /// Builds an engine whose three directories point at the temp fixtures
    /// and whose backups land in `backupRoot` (or a caller-supplied root).
    private func makeEngine(
        backupRoot: URL? = nil,
        auditLogger: AuditLogger? = nil
    ) -> DeepCleanEngine {
        DeepCleanEngine(
            backupManager: BackupManager(rootURL: backupRoot ?? self.backupRoot),
            auditLogger: auditLogger,
            launchAgentsURL: launchAgentsDir,
            launchDaemonsURL: launchDaemonsDir,
            preferencePanesURL: prefPanesDir
        )
    }

    /// Writes a launchd-style plist at `fileURL`. Uses
    /// `PropertyListSerialization` so the test never depends on the
    /// `NSDictionary.write(to:atomically:)` throwing contract.
    private func writePlist(_ dict: [String: Any], to fileURL: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: dict,
            format: .xml,
            options: 0
        )
        try data.write(to: fileURL)
    }

    /// Writes a `.plist` launch agent/daemon file returning its URL.
    @discardableResult
    private func makeLaunchdPlist(
        named name: String,
        label: String,
        in dir: URL
    ) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try writePlist([
            "Label": label,
            "ProgramArguments": ["/usr/bin/false"],
        ], to: url)
        return url
    }

    /// Creates an `AuditLogger` writing to the temp audit log.
    private func makeAuditLogger() throws -> AuditLogger {
        try AuditLogger(logURL: auditLogURL)
    }

    // MARK: - Scan

    /// Every scanned directory missing on disk must degrade to an empty
    /// contribution instead of failing the whole scan.
    func testScanDegradesWhenDirectoriesMissing() async throws {
        let missing = tempDir.appendingPathComponent("does-not-exist")
        let engine = DeepCleanEngine(
            backupManager: BackupManager(rootURL: backupRoot),
            auditLogger: nil,
            launchAgentsURL: missing,
            launchDaemonsURL: missing,
            preferencePanesURL: missing
        )

        let items = try await engine.scan()

        XCTAssertTrue(items.isEmpty, "Unreadable directories must degrade to no items")
    }

    /// A `.plist` file must surface its launchd `Label` as the display
    /// name, and Apple-owned labels must be flagged `isProtected`.
    func testScanReadsLabelsAndFlagsAppleItems() async throws {
        try makeLaunchdPlist(named: "user-agent.plist", label: "com.example.agent", in: launchAgentsDir)
        try makeLaunchdPlist(named: "apple-daemon.plist", label: "com.apple.daemon", in: launchDaemonsDir)
        // A non-plist file in LaunchAgents is ignored.
        try Data("not a plist".utf8).write(to: launchAgentsDir.appendingPathComponent("README.txt"))
        let engine = makeEngine()

        let items = try await engine.scan()

        XCTAssertEqual(items.count, 2)
        let userItem = items.first { $0.url.lastPathComponent == "user-agent.plist" }
        let appleItem = items.first { $0.url.lastPathComponent == "apple-daemon.plist" }
        XCTAssertEqual(userItem?.displayName, "com.example.agent")
        XCTAssertEqual(userItem?.category, .launchAgents)
        XCTAssertEqual(userItem?.isProtected, false)
        XCTAssertEqual(appleItem?.displayName, "com.apple.daemon")
        XCTAssertEqual(appleItem?.category, .launchDaemons)
        XCTAssertEqual(appleItem?.isProtected, true)
    }

    /// A `.prefPane` bundle is scanned as a directory and derives its
    /// display name + bundle ID from its `Contents/Info.plist`.
    func testScanMapsPreferencePaneBundle() async throws {
        let paneDir = prefPanesDir.appendingPathComponent("Example.prefPane")
        let contentsDir = paneDir.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)
        try writePlist([
            "CFBundleDisplayName": "Example Pane",
            "CFBundleIdentifier": "com.example.pane",
        ], to: contentsDir.appendingPathComponent("Info.plist"))
        try Data("payload".utf8).write(to: paneDir.appendingPathComponent("payload.bin"))
        let engine = makeEngine()

        let items = try await engine.scan()

        XCTAssertEqual(items.count, 1)
        guard let pane = items.first else { return }
        XCTAssertEqual(pane.category, .preferencePanes)
        XCTAssertEqual(pane.displayName, "Example Pane")
        XCTAssertEqual(pane.associatedBundleID, "com.example.pane")
        XCTAssertGreaterThan(pane.sizeBytes, 0, "Recursive size walk must include bundle children")
        XCTAssertEqual(pane.isProtected, false)
    }

    /// A preference pane whose folder name is NOT Apple-prefixed must still
    /// be flagged `isProtected` when its `Contents/Info.plist` declares a
    /// `com.apple.*` `CFBundleIdentifier` — protection keys off the bundle
    /// ID when available, never the folder name.
    func testScanProtectsPrefPaneByBundleIdentifier() async throws {
        let paneDir = prefPanesDir.appendingPathComponent("MyUtility.prefPane")
        let contentsDir = paneDir.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)
        try writePlist([
            "CFBundleDisplayName": "My Utility",
            "CFBundleIdentifier": "com.apple.someinternal",
        ], to: contentsDir.appendingPathComponent("Info.plist"))
        let engine = makeEngine()

        let items = try await engine.scan()

        XCTAssertEqual(items.count, 1)
        guard let pane = items.first else { return }
        XCTAssertEqual(pane.category, .preferencePanes)
        XCTAssertEqual(pane.associatedBundleID, "com.apple.someinternal")
        XCTAssertEqual(pane.isProtected, true, "A com.apple.* bundle ID must protect the pane regardless of its folder name")
    }

    /// A launch agent that launches an Apple app via `ProgramArguments` must
    /// NOT be flagged protected when its label is third-party — the derived
    /// bundle ID is surfaced for display but never drives protection.
    func testScanLaunchAgentNotProtectedWhenProgramArgumentsLaunchesAppleApp() async throws {
        // Hermetic Apple-owned .app fixture — no dependency on the host's
        // /Applications (Safari may be absent or renamed).
        let appleAppDir = tempDir.appendingPathComponent("Apple.app")
        let contentsDir = appleAppDir.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)
        try writePlist([
            "CFBundleIdentifier": "com.apple.someinternal",
        ], to: contentsDir.appendingPathComponent("Info.plist"))

        try writePlist([
            "Label": "com.thirdparty.someagent",
            "ProgramArguments": ["/usr/bin/open", appleAppDir.path],
        ], to: launchAgentsDir.appendingPathComponent("thirdparty-agent.plist"))
        let engine = makeEngine()

        let items = try await engine.scan()

        guard let agent = items.first else {
            return XCTFail("Expected the launch agent to be scanned")
        }
        XCTAssertEqual(agent.category, .launchAgents)
        XCTAssertEqual(agent.associatedBundleID, "com.apple.someinternal",
                       "The Apple app bundle ID is derived for display even though it does not drive protection")
        XCTAssertEqual(agent.isProtected, false,
                       "A third-party launch agent must never be protected via a ProgramArguments-derived bundle ID")
    }

    /// A launch agent whose label IS Apple-owned stays protected even when its
    /// `ProgramArguments` names a third-party app — the label invariant wins.
    func testScanLaunchAgentAppleLabelStaysProtectedDespiteThirdPartyProgramArguments() async throws {
        try writePlist([
            "Label": "com.apple.someagent",
            "ProgramArguments": ["/usr/bin/open", "/Applications/SomeThirdParty.app"],
        ], to: launchAgentsDir.appendingPathComponent("apple-agent.plist"))
        let engine = makeEngine()

        let items = try await engine.scan()

        guard let agent = items.first else {
            return XCTFail("Expected the launch agent to be scanned")
        }
        XCTAssertEqual(agent.category, .launchAgents)
        XCTAssertEqual(agent.isProtected, true,
                       "An Apple-owned label must stay protected regardless of ProgramArguments content")
    }

    // MARK: - Clean

    /// An empty selection is a no-op returning zero.
    func testCleanEmptyReturnsZero() async throws {
        let engine = makeEngine()

        let deleted = try await engine.clean([])

        XCTAssertEqual(deleted, 0)
    }

    /// Apple-owned items are silently skipped — never deleted, never
    /// backed up.
    func testCleanSkipsProtectedItems() async throws {
        try makeLaunchdPlist(named: "apple.plist", label: "com.apple.thing", in: launchAgentsDir)
        let engine = makeEngine()
        let items = try await engine.scan()
        let protected = items.first { $0.isProtected }

        let deleted = try await engine.clean(protected.map { [$0] } ?? [])

        XCTAssertEqual(deleted, 0)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: launchAgentsDir.appendingPathComponent("apple.plist").path),
            "Protected items must never be deleted"
        )
    }

    /// The engine must back up before deleting: after `clean`, the file is
    /// gone AND a versioned backup + manifest exist under the bundle ID.
    func testCleanBacksUpBeforeDeleting() async throws {
        try makeLaunchdPlist(named: "user.plist", label: "com.example.user", in: launchAgentsDir)
        let engine = makeEngine()
        let items = try await engine.scan()
        let deletable = items.filter { !$0.isProtected }

        let deleted = try await engine.clean(deletable)

        XCTAssertEqual(deleted, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: launchAgentsDir.appendingPathComponent("user.plist").path),
            "Selected item must be deleted after a successful backup"
        )
        let manifestURL = backupRoot
            .appendingPathComponent(DeepCleanEngine.backupBundleID)
            .appendingPathComponent("v1")
            .appendingPathComponent("manifest.json")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: manifestURL.path),
            "Backup manifest must exist after a clean"
        )
    }

    /// When the pre-delete backup fails, the whole operation must abort:
    /// nothing is deleted and the failure is audited.
    func testCleanAbortsWhenBackupFails() async throws {
        try makeLaunchdPlist(named: "user.plist", label: "com.example.user", in: launchAgentsDir)
        // Backup root is a regular FILE, so createDirectory inside `backup`
        // throws and the clean must abort before any delete.
        let fileAsRoot = tempDir.appendingPathComponent("root-file")
        try Data("x".utf8).write(to: fileAsRoot)
        let engine = makeEngine(backupRoot: fileAsRoot, auditLogger: try makeAuditLogger())
        let items = try await engine.scan()

        do {
            _ = try await engine.clean(items.filter { !$0.isProtected })
            XCTFail("Expected clean to rethrow the backup failure")
        } catch {
            // Expected: backup threw.
        }

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: launchAgentsDir.appendingPathComponent("user.plist").path),
            "A failed backup must abort the clean before any delete"
        )
        let events = try await makeAuditLogger().recentEvents(limit: 5)
        XCTAssertEqual(events.first?.action, "deepclean-backup")
        XCTAssertEqual(events.first?.status, "failure")
    }

    /// A single un-deletable path must not block the rest: the surviving
    /// items still get deleted, and both outcomes are audited.
    func testCleanContinuesPastPerItemDeleteFailures() async throws {
        let existingURL = try makeLaunchdPlist(named: "a.plist", label: "com.example.a", in: launchAgentsDir)
        let vanishedURL = try makeLaunchdPlist(named: "b.plist", label: "com.example.b", in: launchAgentsDir)
        let engine = makeEngine(auditLogger: try makeAuditLogger())
        let items = try await engine.scan()
        // Simulate a file that vanished between scan and clean.
        try FileManager.default.removeItem(at: vanishedURL)

        let deleted = try await engine.clean(items.filter { !$0.isProtected })

        XCTAssertEqual(deleted, 1, "Only the still-existing file can be deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: existingURL.path))
        let events = try await makeAuditLogger().recentEvents(limit: 5)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(Set(events.map(\.status)), ["success", "failure"])
    }
}
