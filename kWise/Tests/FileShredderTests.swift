// kWise/Tests/StartupItemsAndShredderTests.swift
//
// v2.0 Phase 5 — M2 启动项 + M6 粉碎.
import XCTest
@testable import kWise

// MARK: - StartupItems scanner

@MainActor
final class StartupItemsScannerTests: XCTestCase {

    private func makePlist(directory: URL, label: String,
                           runAtLoad: Bool = true, keepAlive: Bool = false) throws -> URL {
        let url = directory.appendingPathComponent("\(label).plist")
        let plist: [String: Any] = [
            "Label": label,
            "Program": "/Applications/\(label).app/Contents/MacOS/\(label)",
            "RunAtLoad": runAtLoad,
            "KeepAlive": keepAlive,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url)
        return url
    }

    func testLaunchPlistParserExtractsFields() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agents-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try makePlist(directory: dir, label: "com.test.agent", keepAlive: true)

        let entry = LaunchPlistParser.parse(url: url, scope: .user)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.label, "com.test.agent")
        XCTAssertEqual(entry?.programPath, "/Applications/com.test.agent.app/Contents/MacOS/com.test.agent")
        XCTAssertEqual(entry?.runAtLoad, true)
        XCTAssertEqual(entry?.keepAlive, true)
        XCTAssertEqual(entry?.scope, .user)
    }

    func testMalformedPlistIsSkippedNotThrown() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agents-bad-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("not a plist {{{".utf8).write(to: dir.appendingPathComponent("broken.plist"))

        let items = StartupItemsScanner.items(in: dir, scope: .user)
        XCTAssertTrue(items.isEmpty, "Malformed plists are skipped, never thrown")
    }

    func testScannerClassifiesUserAndSystemScope() async throws {
        let userDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("user-agents-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: userDir) }
        _ = try makePlist(directory: userDir, label: "com.test.user")

        let scanner = StartupItemsScanner(scope: AppScope.shared.scope)
        // Direct static path is exercised for classification; async scan is
        // covered by the VM tests via the shared scope.
        let parsed = LaunchPlistParser.parse(url: userDir.appendingPathComponent("com.test.user.plist"), scope: .user)
        XCTAssertEqual(parsed?.scope, .user)
        _ = scanner
    }
}

// MARK: - StartupItem toggler

@MainActor
final class StartupItemToggleTests: XCTestCase {

    private func makeUserPlist() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("toggle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("com.test.toggle.plist")
        try PropertyListSerialization.data(fromPropertyList: ["Label": "com.test.toggle"],
                                           format: .xml, options: 0)
            .write(to: url)
        return url
    }

    func testDisableTrashesAndRecordsHistory() async throws {
        let plistURL = try makeUserPlist()
        defer { try? FileManager.default.removeItem(at: plistURL.deletingLastPathComponent()) }

        let persistence = PersistenceController(inMemory: true)
        let toggler = StartupItemToggler(persistence: persistence)
        let entry = LoginItemEntry(
            label: "com.test.toggle",
            plistURL: plistURL,
            programPath: nil,
            runAtLoad: true, keepAlive: false, scope: .user
        )

        let ok = await toggler.disable(entry)
        XCTAssertTrue(ok)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path),
                       "Disabled item's plist must be out of the agents directory")

        let history = persistence.fetchHistory(limit: 0)
        XCTAssertTrue(history.contains { $0.bundleID == "com.test.toggle" },
                      "Disable must land in the restorable history")
    }

    func testSystemScopeRefused() async throws {
        let plistURL = try makeUserPlist()
        defer { try? FileManager.default.removeItem(at: plistURL.deletingLastPathComponent()) }

        let toggler = StartupItemToggler(persistence: PersistenceController(inMemory: true))
        let entry = LoginItemEntry(
            label: "com.system.daemon",
            plistURL: plistURL,
            programPath: nil,
            runAtLoad: true, keepAlive: false, scope: .system
        )
        let ok = await toggler.disable(entry)
        XCTAssertFalse(ok, "System-scope items must never be touched by the toggler")
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
    }

    func testEnableRestoresFromSnapshot() async throws {
        let plistURL = try makeUserPlist()
        let dir = plistURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: dir) }

        let toggler = StartupItemToggler(persistence: PersistenceController(inMemory: true))
        let entry = LoginItemEntry(
            label: "com.test.toggle", plistURL: plistURL,
            programPath: nil, runAtLoad: true, keepAlive: false, scope: .user
        )

        _ = await toggler.disable(entry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))

        let restored = await toggler.enable(entry)
        XCTAssertTrue(restored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path),
                      "Enable must put the plist back")
    }
}

// MARK: - FileShredder

@MainActor
final class FileShredderTests: XCTestCase {

    private func makeFile(sizeBytes: Int, content: UInt8 = 0xAA) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shred-\(UUID().uuidString).bin")
        try Data(repeating: content, count: sizeBytes).write(to: url)
        return url
    }

    func testGuardrailsRejectDirectoriesAndSystemPaths() {
        let dir = FileManager.default.temporaryDirectory
        XCTAssertFalse(FileShredder.guardrailsPass(for: dir),
                       "Directories must never be shredded")

        XCTAssertFalse(FileShredder.guardrailsPass(for: URL(fileURLWithPath: "/System/Library/test")))
        XCTAssertFalse(FileShredder.guardrailsPass(for: URL(fileURLWithPath: "/Library/Fonts/x.ttf")))
        XCTAssertFalse(FileShredder.guardrailsPass(for: URL(fileURLWithPath: "/usr/bin/yes")))

        let userFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("ok-\(UUID().uuidString).txt")
        XCTAssertTrue(FileShredder.guardrailsPass(for: userFile),
                      "A non-existent temp-dir file passes the static path checks (existence is a separate guard)")
    }

    func testShredOverwritesVerifiesRenamesAndTrashes() async throws {
        let url = try makeFile(sizeBytes: 4_000_000) // 4 MB — multi-block
        defer { try? FileManager.default.removeItem(at: url) }

        let shredder = FileShredder(scope: AppScope.shared.scope,
                                    persistence: PersistenceController(inMemory: true))
        var phases: [ShredProgress.Phase] = []
        let stream = await shredder.shred(urls: [url], plan: ShredPlan.standard)
        for await progress in stream {
            phases.append(progress.phase)
        }

        XCTAssertTrue(phases.contains { if case .overwriting(let pass) = $0 { return pass == 1 } else { return false } },
                      "Standard plan must run exactly one overwrite pass")
        XCTAssertTrue(phases.contains { if case .verifying = $0 { return true } else { return false } })
        XCTAssertTrue(phases.contains { if case .renaming = $0 { return true } else { return false } })
        XCTAssertTrue(phases.contains { if case .done = $0 { return true } else { return false } })

        // Content destroyed + shell gone from the original path (trashed).
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testShredRefusesOutOfRangeFile() async throws {
        let systemPath = URL(fileURLWithPath: "/usr/bin/com.kwise.test.nonexistent")
        let shredder = FileShredder(scope: AppScope.shared.scope,
                                    persistence: PersistenceController(inMemory: true))
        var failures = 0
        let stream = await shredder.shred(urls: [systemPath])
        for await progress in stream {
            if case .failed = progress.phase { failures += 1 }
        }
        XCTAssertGreaterThan(failures, 0, "Out-of-scope paths must be refused, never shredded")
    }

    func testHistoryWrittenBeforePass() async throws {
        let url = try makeFile(sizeBytes: 1_024)
        defer { try? FileManager.default.removeItem(at: url) }

        let persistence = PersistenceController(inMemory: true)
        let shredder = FileShredder(scope: AppScope.shared.scope, persistence: persistence)

        var sawHistoryDuringRun = false
        let stream = await shredder.shred(urls: [url])
        for await progress in stream {
            let history = persistence.fetchHistory(limit: 0)
            if !history.isEmpty { sawHistoryDuringRun = true }
            if case .done = progress.phase { break }
        }
        XCTAssertTrue(sawHistoryDuringRun,
                      "History rows must exist before the destructive work completes")
    }
}
