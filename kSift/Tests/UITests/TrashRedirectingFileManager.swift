import Foundation

/// Test-only `FileManager` that intercepts both `removeItem(at:)` and
/// `trashItem(at:resultingItemURL:)` and reroutes the affected file into a
/// private "trash" directory instead of actually unlinking or trashing it.
///
/// Used by `ResultViewModelTests.makeVaultCleanupManager` to exercise the
/// full VaultManager copy + remove flow without touching the host's Trash.
/// Copy, directory creation, and existence checks pass through unchanged.
///
/// `trashedPaths` exposes every URL the test redirected, so assertions can
/// confirm the right files were moved. `failTrashPaths` makes the next
/// trash/remove for the matching path throw, so failure-path tests can
/// exercise `VaultManager`'s error handling without monkey-patching.
final class TrashRedirectingFileManager: FileManager, @unchecked Sendable {
    private let trashRoot: URL
    private let lock = NSLock()
    private var _trashedPaths: [URL] = []
    private var _failTrashPaths: Set<String> = []

    /// Read-only view of every path that successfully landed in the test
    /// trash. Updated under `lock`.
    var trashedPaths: [URL] {
        lock.lock(); defer { lock.unlock() }
        return _trashedPaths
    }

    /// Paths for which the next `removeItem(at:)` or
    /// `trashItem(at:resultingItemURL:)` should throw, simulating a Trash
    /// that refuses the move (e.g. file locked, permission denied).
    var failTrashPaths: Set<String> {
        get {
            lock.lock(); defer { lock.unlock() }
            return _failTrashPaths
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _failTrashPaths = newValue
        }
    }

    init(trashRoot: URL) {
        self.trashRoot = trashRoot
        super.init()
        try? FileManager.default.createDirectory(
            at: trashRoot, withIntermediateDirectories: true)
    }

    /// Returns a unique destination URL inside the test trash so two
    /// originals with the same `lastPathComponent` don't collide.
    private func nextDestination(for url: URL) -> URL {
        let base = url.lastPathComponent
        let candidate = trashRoot.appendingPathComponent(base)
        var attempt = candidate
        var n = 1
        while FileManager.default.fileExists(atPath: attempt.path) {
            attempt = trashRoot.appendingPathComponent("\(n)_\(base)")
            n += 1
        }
        return attempt
    }

    override func removeItem(at URL: URL) throws {
        lock.lock()
        let shouldFail = _failTrashPaths.contains(URL.path)
        lock.unlock()
        if shouldFail {
            throw NSError(
                domain: "TrashRedirectingFileManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Simulated trash failure for \(URL.path)"]
            )
        }
        let destination = nextDestination(for: URL)
        try FileManager.default.moveItem(at: URL, to: destination)
        lock.lock()
        _trashedPaths.append(URL)
        lock.unlock()
    }

    override func trashItem(
        at url: URL,
        resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?
    ) throws {
        lock.lock()
        let shouldFail = _failTrashPaths.contains(url.path)
        lock.unlock()
        if shouldFail {
            throw NSError(
                domain: "TrashRedirectingFileManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Simulated trash failure for \(url.path)"]
            )
        }
        let destination = nextDestination(for: url)
        try FileManager.default.moveItem(at: url, to: destination)
        if let outResultingURL {
            outResultingURL.pointee = destination as NSURL
        }
        lock.lock()
        _trashedPaths.append(url)
        lock.unlock()
    }
}