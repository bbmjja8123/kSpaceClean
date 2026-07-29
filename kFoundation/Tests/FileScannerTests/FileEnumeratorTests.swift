// kFoundation/Tests/FileEnumeratorTests.swift
//
// Coverage for ``FileEnumerator``:
// - Happy-path enumeration produces the expected number of entries
// - Skip prefixes cause the walker to bail out before descending further
// - Cooperative cancellation via ``CancellationToken``
//
// The walker's TCC behaviour is exercised indirectly: when ``FileManager``
// cannot enter a directory the enumerator simply stops emitting entries
// for that branch (no throw), so we don't need to assert anything specific
// about TCC here — that's covered at the orchestrator layer (B3+).

import XCTest
@testable import FileScanner

final class FileEnumeratorTests: XCTestCase {

    /// Helper: build a fresh temp directory tree for a single test. Returns
    /// the root URL and a teardown closure so each test can independently
    /// create files without interference.
    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileEnumeratorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func testEnumeratesFiles() async throws {
        // Create a tiny tree:
        //   <temp>/
        //     a.txt
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        try "test".write(
            to: tempDir.appendingPathComponent("a.txt"),
            atomically: true,
            encoding: .utf8
        )

        let enumerator = FileEnumerator()
        var count = 0
        for await info in await enumerator.enumerate(rootPath: tempDir.path) {
            if info.path.hasSuffix("a.txt") { count += 1 }
        }

        XCTAssertEqual(count, 1)
    }

    func testEnumeratesRecursiveTree() async throws {
        // Create a slightly deeper tree:
        //   <temp>/
        //     a.txt
        //     sub/
        //       b.txt
        //       deeper/
        //         c.txt
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        try "a".write(
            to: tempDir.appendingPathComponent("a.txt"),
            atomically: true,
            encoding: .utf8
        )
        let sub = tempDir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "b".write(
            to: sub.appendingPathComponent("b.txt"),
            atomically: true,
            encoding: .utf8
        )
        let deeper = sub.appendingPathComponent("deeper")
        try FileManager.default.createDirectory(at: deeper, withIntermediateDirectories: true)
        try "c".write(
            to: deeper.appendingPathComponent("c.txt"),
            atomically: true,
            encoding: .utf8
        )

        let enumerator = FileEnumerator()
        var paths: Set<String> = []
        for await info in await enumerator.enumerate(rootPath: tempDir.path) {
            if !info.isDirectory {
                paths.insert(info.path)
            }
        }

        XCTAssertEqual(paths.count, 3)
        XCTAssertTrue(paths.contains(where: { $0.hasSuffix("a.txt") }))
        XCTAssertTrue(paths.contains(where: { $0.hasSuffix("b.txt") }))
        XCTAssertTrue(paths.contains(where: { $0.hasSuffix("c.txt") }))
    }

    func testSkipPathsAreRespected() async throws {
        // The walker should never descend into ``skipPaths``. We arrange a
        // sentinel file inside the skipped subtree and assert it is not
        // yielded.
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        try "kept".write(
            to: tempDir.appendingPathComponent("kept.txt"),
            atomically: true,
            encoding: .utf8
        )
        let skippedDir = tempDir.appendingPathComponent("skipped")
        try FileManager.default.createDirectory(at: skippedDir, withIntermediateDirectories: true)
        try "hidden".write(
            to: skippedDir.appendingPathComponent("hidden.txt"),
            atomically: true,
            encoding: .utf8
        )

        let enumerator = FileEnumerator()
        var paths: Set<String> = []
        // Standardize so the path matches what the walker will see after
        // ``URL.standardizedFileURL`` (macOS resolves ``/var/folders`` to
        // ``/private/var/folders`` etc.).
        let skipPaths: Set<String> = [skippedDir.standardizedFileURL.path]
        for await info in await enumerator.enumerate(
            rootPath: tempDir.path,
            skipPaths: skipPaths
        ) {
            if !info.isDirectory {
                paths.insert(info.path)
            }
        }

        XCTAssertTrue(paths.contains(where: { $0.hasSuffix("kept.txt") }))
        XCTAssertFalse(paths.contains(where: { $0.hasSuffix("hidden.txt") }))
    }

    func testCancellationToken() {
        // The callback-based API uses ``CancellationToken`` to short-circuit
        // long scans; the token must flip correctly.
        let token = CancellationToken()
        XCTAssertFalse(token.isCancelled)
        token.cancel()
        XCTAssertTrue(token.isCancelled)
    }

    func testCallbackEnumerateReportsFiles() async throws {
        // Smoke test for the callback-based overload: every non-directory
        // entry inside ``tempDir`` should be reported exactly once.
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        try "1".write(
            to: tempDir.appendingPathComponent("one.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "2".write(
            to: tempDir.appendingPathComponent("two.txt"),
            atomically: true,
            encoding: .utf8
        )

        let enumerator = FileEnumerator()
        let token = CancellationToken()
        // Counter must be Sendable to be safely captured by the @Sendable
        // progress closure under strict concurrency. A small final class
        // with a lock-free atomic counter is the cheapest option here.
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var _value = 0
            func increment() { lock.lock(); _value += 1; lock.unlock() }
            var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
        }
        let counter = Counter()

        try await enumerator.enumerate(
            root: tempDir,
            progressHandler: { _ in counter.increment() },
            cancellationToken: token
        )

        XCTAssertEqual(counter.value, 2)
    }
}