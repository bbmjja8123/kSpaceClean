import Foundation
import os

/// Polling service that monitors the user Trash directory size.
///
/// Runs a lightweight loop every 30 seconds. When the trash exceeds 1 GB
/// it posts a `trashSizeExceeded` notification so the rest of the app can
/// react (e.g., show a badge, suggest cleanup).
///
/// This service is designed to be started from the app's `AppDelegate` or
/// `AppCoordinator`; it is **not** a standalone launch-agent binary.
///
/// ## Thread Safety
///
/// Mutable state (`_isRunning`) is guarded by an `NSLock` so that `start()`
/// and `stop()` can be called from any thread without a data race. The
/// polling loop itself runs within a Swift Concurrency `Task`.
public final class TrashMonitorService: @unchecked Sendable {
    // MARK: - Constants

    private let pollInterval: TimeInterval = 30
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "app.kraftly.kspaceclean", category: "TrashMonitor")

    // MARK: - State

    private let lock = NSLock()
    private var _isRunning = false
    private var pollingTask: Task<Void, Never>?

    // MARK: - Public API

    public init() {}

    /// Start monitoring the trash directory.
    ///
    /// If the service is already running this is a no-op.
    public func start() {
        lock.lock()
        if _isRunning {
            lock.unlock()
            return
        }
        _isRunning = true
        lock.unlock()

        pollingTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                self.checkTrashSize()

                do {
                    try await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
                } catch {
                    // Task was cancelled while sleeping; exit the loop.
                    break
                }
            }

            self.lock.lock()
            self._isRunning = false
            self.lock.unlock()
        }
    }

    /// Stop monitoring the trash directory.
    ///
    /// Cancels the polling task and marks the service as stopped.
    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil

        lock.lock()
        _isRunning = false
        lock.unlock()
    }

    /// Whether the service is currently polling.
    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRunning
    }

    // MARK: - Private

    /// Check the current trash size and post a notification if it exceeds 1 GB.
    private func checkTrashSize() {
        guard let trashURL = fileManager.urls(for: .trashDirectory, in: .userDomainMask).first else {
            logger.debug("Could not resolve trash directory URL")
            return
        }

        let size = directorySize(trashURL)
        logger.debug("Trash size: \(size) bytes")

        if size > 1_000_000_000 {
            NotificationCenter.default.post(
                name: .trashSizeExceeded,
                object: nil,
                userInfo: ["size": size, "url": trashURL]
            )
        }
    }

    /// Recursively compute the total size (in bytes) of all files under the
    /// given directory URL.
    ///
    /// - Parameter url: The directory to scan.
    /// - Returns: Aggregate file size in bytes.
    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                continue
            }
            total += Int64(size)
        }
        return total
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    /// Posted when the Trash directory exceeds 1 GB.
    ///
    /// The `userInfo` dictionary contains:
    /// - `"size"` (`Int64`): The total size in bytes.
    /// - `"url"` (`URL`): The Trash directory URL.
    static let trashSizeExceeded = Notification.Name("com.kraftly.kspaceclean.trashSizeExceeded")
}
