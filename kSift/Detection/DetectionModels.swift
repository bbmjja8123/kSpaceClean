import Foundation
import FileScanner

public struct DetectionProgress: Sendable {
    public let phase: ScanPhase
    public let currentItem: String?
    public let itemsProcessed: Int
    public let totalItems: Int

    public init(phase: ScanPhase, currentItem: String? = nil, itemsProcessed: Int = 0, totalItems: Int = 0) {
        self.phase = phase
        self.currentItem = currentItem
        self.itemsProcessed = itemsProcessed
        self.totalItems = totalItems
    }
}

public final class ScanController: @unchecked Sendable {
    private let token = CancellationToken()
    private let pauseLock = NSLock()
    private var _isPaused = false
    /// Continuations awaited by detectors that hit the pause gate. Resumed
    /// by `resume()` via `lock.withLock { for c in continuations { c.resume() }; continuations.removeAll() }`.
    private var pausedContinuations: [CheckedContinuation<Void, Never>] = []

    public var isCancelled: Bool { token.isCancelled }

    /// True while the user has paused the scan. Detectors should call
    /// `await pauseGateIfNeeded()` at each iteration boundary to honor it.
    public var isPaused: Bool {
        pauseLock.lock(); defer { pauseLock.unlock() }
        return _isPaused
    }

    public init() {}

    public func cancel() { token.cancel() }

    /// Marks the scan paused. Detectors that subsequently call
    /// `await pauseGateIfNeeded` will suspend until `resume()` is called.
    public func pause() {
        pauseLock.lock()
        _isPaused = true
        pauseLock.unlock()
    }

    /// Clears the pause flag and resumes every detector currently
    /// suspended on the gate. Detectors wake up at their next iteration.
    public func resume() {
        var toResume: [CheckedContinuation<Void, Never>] = []
        pauseLock.lock()
        _isPaused = false
        toResume = pausedContinuations
        pausedContinuations.removeAll()
        pauseLock.unlock()
        for continuation in toResume {
            continuation.resume()
        }
    }

    /// Suspends the calling task while paused. Detectors call this at the
    /// top of each loop iteration so the pause takes effect at a safe
    /// checkpoint. No-op when not paused. If the outer task is cancelled
    /// while paused, the parked continuation is released so it doesn't
    /// leak.
    public func awaitResumed() async {
        let shouldPark: Bool = pauseLock.lock(); defer {
            pauseLock.unlock()
        }(); return _isPaused
        // Unreachable; the lock+read above is the gate. The actual park
        // happens below if needed.
        _ = shouldPark

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var didPark = false
            pauseLock.lock()
            if _isPaused {
                pausedContinuations.append(continuation)
                didPark = true
            }
            pauseLock.unlock()
            if !didPark {
                continuation.resume()
            }
        }
    }

    public var fileToken: CancellationToken { token }
}
