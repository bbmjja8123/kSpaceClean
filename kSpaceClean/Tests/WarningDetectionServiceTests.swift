// kSpaceClean/Features/Cleanup/Tests/WarningDetectionServiceTests.swift
//
// Task C3 — WarningDetectionService (Layer 1) tests.
//
// The detector enumerates every PID on the system via `libproc`, which is
// side-effecting and depends on what the machine happens to be running. The
// tests below split into two groups:
//
// - **Pure paths**: the early-return guards for empty / nonexistent input.
// - **Self-detection (C7)**: the test process opens a real file, then asks the
//   service whether anything has that path open. Because the test runner *is*
//   a running process with the file open, a correct libproc implementation
//   must find it. This is the regression guard for C7 — the previous `lsof`
//   implementation returned nothing at all under App Sandbox, and no unit
//   test caught it because every test only asserted "empty".
import XCTest
@testable import kSpaceClean

final class WarningDetectionServiceTests: XCTestCase {

    // MARK: - Empty selection

    /// No paths → no work, no warnings.
    func testDetectWarnItemsEmpty() async {
        let service = WarningDetectionService()
        let result = await service.detectWarnItems(for: [])
        XCTAssertEqual(result.count, 0)
    }

    /// A single non-existent path is filtered out by the standardise step
    /// (which returns "" for files that do not exist), so we still get an
    /// empty result without raising.
    func testDetectWarnItemsSkipsNonexistentPaths() async {
        let service = WarningDetectionService()
        let result = await service.detectWarnItems(for: ["/tmp/does-not-exist-\(UUID().uuidString)"])
        XCTAssertEqual(result.count, 0)
    }

    // MARK: - C7 regression: libproc actually resolves paths

    /// The FD-enumeration path must return real absolute paths for the
    /// *current* process.
    ///
    /// This bypasses the `NSWorkspace` attribution step (the test runner is
    /// not a GUI app, so it would never appear in `runningApplications` and
    /// `detectWarnItems` would correctly filter it out). Instead we assert the
    /// layer underneath: given a file this process holds open, the FD walk
    /// must surface it. If C7 regresses to a subprocess-based implementation
    /// that the sandbox blocks, this returns an empty array and the test
    /// fails.
    func testOpenFilesFindsFileHeldOpenByThisProcess() throws {
        // Use /tmp directly so we sidestep the /var/folders -> /private/var
        // symlink that Xcode's NSTemporaryDirectory returns. The
        // assertion checks several aliases because /tmp is itself a
        // symlink on some macOS installs.
        let dir = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("sclean-warn-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("held-open.bin")
        try Data(repeating: 0xAB, count: 4096).write(to: file)

        // Hold a descriptor open for the duration of the assertion.
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        // Try every plausible alias the kernel / our enumerator might return.
        let candidates: [String] = [
            file.path,
            file.resolvingSymlinksInPath().path,
            "/private" + file.path,
            URL(fileURLWithPath: "/private/tmp")
                .appendingPathComponent(dir.lastPathComponent)
                .appendingPathComponent("held-open.bin").path
        ]
        let opened = WarningDetectionService.openFilesForTesting(pid: getpid())

        XCTAssertFalse(opened.isEmpty,
                       "libproc FD enumeration returned nothing for the current process — "
                       + "the C7 in-process implementation is not working")
        let hit = candidates.contains(where: { opened.contains($0) })
        XCTAssertTrue(hit,
                      "expected one of \(candidates) among the open files; "
                      + "got \(opened.count) paths (sample: \(opened.prefix(5)))")
    }

    /// Every path the FD walk returns must be an absolute path — no relative
    /// fragments, no pseudo-paths, no garbage read out of the struct tail.
    func testOpenFilesReturnsOnlyAbsolutePaths() {
        let opened = WarningDetectionService.openFilesForTesting(pid: getpid())
        for path in opened {
            XCTAssertTrue(path.hasPrefix("/"), "non-absolute path leaked from FD walk: \(path)")
            XCTAssertFalse(path.contains("\0"), "embedded NUL leaked from FD walk: \(path)")
        }
    }

    /// PID 0 (the kernel) has no introspectable FD table from user space; the
    /// implementation must degrade to an empty array rather than crash or
    /// return garbage.
    func testOpenFilesForKernelPIDIsEmpty() {
        let opened = WarningDetectionService.openFilesForTesting(pid: 0)
        XCTAssertTrue(opened.isEmpty)
    }
}
