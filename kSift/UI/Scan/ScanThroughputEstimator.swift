import Foundation

/// Estimates scan throughput and remaining time from the orchestrator's
/// progress events. Pure value type — no timers, no engine coupling: the
/// view model feeds `record(...)` on each `.progress` event and reads
/// `filesPerSecond` / `estimatedRemaining(progress:)` for display.
///
/// Rates are EWMA-smoothed because the engine's phase fractions step
/// discretely (0.15 → 0.2 → 0.4 …), so raw deltas bounce between 0 and
/// huge values. A zero progress delta (phase boundaries) yields a nil ETA
/// rather than ∞.
struct ScanThroughputEstimator {
    /// Smoothing factor for the EWMA over per-sample rates (0..1).
    /// 0.2 ≈ last 5 samples dominate, enough to absorb phase-step noise.
    private let smoothing: Double

    private var lastTimestamp: TimeInterval?
    private var lastProgress: Double = 0
    private var lastFilesScanned: Int = 0
    private var smoothedFilesPerSecond: Double?
    private var smoothedProgressPerSecond: Double?

    init(smoothing: Double = 0.2) {
        self.smoothing = min(max(smoothing, 0.01), 1.0)
    }

    /// Feeds one progress sample. `timestamp` is monotonic-ish wall time
    /// in seconds (the caller typically passes the elapsed scan time).
    mutating func record(filesScanned: Int, progress: Double, at timestamp: TimeInterval) {
        defer {
            lastTimestamp = timestamp
            lastProgress = progress
            lastFilesScanned = filesScanned
        }
        guard let last = lastTimestamp else { return }
        let dt = timestamp - last
        guard dt > 0.05 else { return } // ignore sub-50 ms bursts

        let dProgress = progress - lastProgress
        let dFiles = filesScanned - lastFilesScanned

        if dFiles >= 0 {
            let rate = Double(dFiles) / dt
            smoothedFilesPerSecond = smoothedFilesPerSecond.map { $0 + smoothing * (rate - $0) } ?? rate
        }
        if dProgress > 0 {
            let rate = dProgress / dt
            smoothedProgressPerSecond = smoothedProgressPerSecond.map { $0 + smoothing * (rate - $0) } ?? rate
        }
    }

    /// Smoothed files/second, nil before two samples arrive.
    var filesPerSecond: Double? {
        smoothedFilesPerSecond
    }

    /// Estimated seconds remaining, nil when the scan hasn't produced a
    /// measurable forward rate yet (or is at/near completion).
    func estimatedRemaining(progress: Double) -> TimeInterval? {
        guard let rate = smoothedProgressPerSecond, rate > 1e-9,
              progress < 1.0 else { return nil }
        let remaining = (1.0 - progress) / rate
        return remaining.isFinite && remaining >= 0 ? remaining : nil
    }

    /// Clears all samples (new scan).
    mutating func reset() {
        lastTimestamp = nil
        lastProgress = 0
        lastFilesScanned = 0
        smoothedFilesPerSecond = nil
        smoothedProgressPerSecond = nil
    }
}
