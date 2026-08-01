import XCTest
@testable import kFresh

/// Coverage for `StartupItemManager` — the actor that lists macOS login items,
/// launch agents, and launch daemons by scanning the standard plist
/// directories and toggling a launch item's `Disabled` key in-place.
///
/// The manager is `internal` and uses the same module-scoped `StartupItem`
/// / `StartupItemType` types defined in `Core/Detect/InstalledApp.swift`,
/// so the tests live in `kFresh` test target via `@testable import`.
///
/// Each test temporarily writes a plist into the system temp directory and
/// cleans it up in `defer` (rather than touching the user's real LaunchAgents)
/// so the suite stays hermetic.
final class StartupItemManagerTests: XCTestCase {

    // MARK: - Fixtures

    /// Creates a fresh .plist file in `NSTemporaryDirectory()` containing
    /// the given dictionary. Returns the URL — callers are expected to
    /// delete it in a `defer` block.
    private func makeTempPlist(_ plist: [String: Any], name: String = UUID().uuidString) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: tmp)
        return tmp
    }

    /// Reads the plist at `url` back into a dictionary, gracefully returning
    /// an empty dict on any error (so a missing file after `remove()` does
    /// not throw in the test).
    private func readPlist(_ url: URL) -> [String: Any] {
        do {
            let ns = try NSDictionary(contentsOf: url)
            return (ns as? [String: Any]) ?? [:]
        } catch {
            return [:]
        }
    }

    /// Builds a `StartupItem` matching the existing internal init signature
    /// (no `id:` label — the id is computed from `url.path`).
    private func makeItem(url: URL, enabled: Bool = true, protectedFlag: Bool = false) -> StartupItem {
        StartupItem(
            name: url.deletingPathExtension().lastPathComponent,
            type: .launchAgent,
            url: url,
            appURL: nil,
            enabled: enabled,
            isProtected: protectedFlag
        )
    }

    // MARK: - Tests

    /// Sanity smoke test — `listItems()` returns a non-nil array even when
    /// none of the standard directories contain anything readable (the
    /// sandboxed test runner will hit missing-path / unreadable errors
    /// which the manager must swallow gracefully).
    func testListItemsReturnsArrayNotThrow() async throws {
        let manager = StartupItemManager()
        let items = try await manager.listItems()
        XCTAssertNotNil(items)
    }

    /// `setEnabled(false)` writes `Disabled = true` into the plist;
    /// `setEnabled(true)` then removes the key. We verify both directions
    /// through the same temp plist.
    func testSetEnabledTogglesDisabledKey() async throws {
        let manager = StartupItemManager()
        let plist: [String: Any] = [
            "Label": "com.kfresh.test",
            "ProgramArguments": ["/bin/echo", "hi"],
        ]
        let tmp = try makeTempPlist(plist, name: "com.kfresh.test.disabled")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let item = makeItem(url: tmp, enabled: true, protectedFlag: false)

        try await manager.setEnabled(false, for: item)
        let reloaded = readPlist(tmp)
        XCTAssertEqual(reloaded["Disabled"] as? Bool, true, "Disabled key must be set when disabling")

        try await manager.setEnabled(true, for: item)
        let reloaded2 = readPlist(tmp)
        XCTAssertNil(reloaded2["Disabled"], "Disabled key must be removed when re-enabling")
    }

    /// `setEnabled` must refuse to write on a protected item (system-level
    /// launch agents / daemons living under `/Library/`). The error path
    /// throws `StartupError.protected` and the file on disk is untouched.
    func testSetEnabledRefusesProtectedItem() async throws {
        let manager = StartupItemManager()
        let original: [String: Any] = ["Label": "com.kfresh.protected", "Disabled": false]
        let tmp = try makeTempPlist(original, name: "com.kfresh.protected")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let item = makeItem(url: tmp, enabled: true, protectedFlag: true)

        do {
            try await manager.setEnabled(false, for: item)
            XCTFail("Expected StartupError.protected for a protected item")
        } catch let error as StartupError {
            switch error {
            case .protected: break  // expected
            default: XCTFail("Expected StartupError.protected, got \(error)")
            }
        }

        // File must NOT have been mutated — original "Disabled": false untouched.
        let after = readPlist(tmp)
        XCTAssertNotEqual(after["Disabled"] as? Bool, true, "Protected item's plist must not be modified")
    }

    /// `remove()` should move the plist to the backup directory and remove
    /// the original file. We seed the backup directory then perform remove
    /// and verify both that the original is gone and that the backup exists.
    func testRemoveMovesPlistToBackup() async throws {
        let manager = StartupItemManager()
        let plist: [String: Any] = ["Label": "com.kfresh.remove"]
        let tmp = try makeTempPlist(plist, name: "com.kfresh.remove")
        let item = makeItem(url: tmp, enabled: true, protectedFlag: false)
        defer {
            // Best-effort: also wipe the backup (the manager creates the dir
            // under ~/Library/Application Support/.../Backups/StartupItems).
            let backupRoot = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/app.kraftly.kfresh/Backups/StartupItems")
            let backup = backupRoot.appendingPathComponent(tmp.lastPathComponent)
            try? FileManager.default.removeItem(at: backup)
        }

        try await manager.remove(item)

        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path), "Original plist should be gone")
        let backupRoot = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/app.kraftly.kfresh/Backups/StartupItems")
        let backup = backupRoot.appendingPathComponent(tmp.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path), "Backup should exist at expected path")
    }
}
