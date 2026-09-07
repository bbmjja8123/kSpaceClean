import XCTest
@testable import kSift

final class ScanThroughputEstimatorTests: XCTestCase {
    func testBeforeFirstSampleNoRates() {
        var estimator = ScanThroughputEstimator()
        estimator.record(filesScanned: 100, progress: 0.15, at: 0)
        XCTAssertNil(estimator.filesPerSecond, "One sample is not a rate")
        XCTAssertNil(estimator.estimatedRemaining(progress: 0.15))
    }

    func testSyntheticFeedProducesFilesPerSecond() {
        var estimator = ScanThroughputEstimator()
        // 1 000 files per second of synthetic progress.
        for second in 0...10 {
            estimator.record(filesScanned: second * 1_000, progress: 0.1 + Double(second) * 0.05, at: Double(second))
        }
        let rate = estimator.filesPerSecond
        XCTAssertNotNil(rate)
        XCTAssertEqual(rate!, 1_000, accuracy: 150, "Smoothed rate tracks the synthetic 1000 files/s feed")
        let eta = estimator.estimatedRemaining(progress: 0.55)
        XCTAssertNotNil(eta)
        // Remaining 45% at 0.05 progress/s = 9 s.
        XCTAssertEqual(eta!, 9, accuracy: 3)
    }

    func testZeroProgressDeltaYieldsNilEta() {
        var estimator = ScanThroughputEstimator()
        // Phase boundaries keep filesScanned moving but progress flat.
        estimator.record(filesScanned: 0, progress: 0.2, at: 0)
        estimator.record(filesScanned: 5_000, progress: 0.2, at: 1)
        estimator.record(filesScanned: 10_000, progress: 0.2, at: 2)
        XCTAssertNotNil(estimator.filesPerSecond, "File rate still measurable")
        XCTAssertNil(estimator.estimatedRemaining(progress: 0.2), "No forward progress → no ETA (never ∞)")
    }

    func testCompletionClampsEtaToNil() {
        var estimator = ScanThroughputEstimator()
        estimator.record(filesScanned: 0, progress: 0.0, at: 0)
        estimator.record(filesScanned: 1_000, progress: 0.5, at: 1)
        XCTAssertNil(estimator.estimatedRemaining(progress: 1.0), "Finished scan has no remaining time")
    }

    func testResetClearsAllSamples() {
        var estimator = ScanThroughputEstimator()
        estimator.record(filesScanned: 0, progress: 0.1, at: 0)
        estimator.record(filesScanned: 1_000, progress: 0.2, at: 1)
        XCTAssertNotNil(estimator.filesPerSecond)
        estimator.reset()
        XCTAssertNil(estimator.filesPerSecond, "Reset clears the rate history")
        estimator.record(filesScanned: 0, progress: 0.0, at: 100)
        XCTAssertNil(estimator.filesPerSecond, "Post-reset single sample is not a rate")
    }

    func testBurstSamplesBelowWindowIgnored() {
        var estimator = ScanThroughputEstimator()
        estimator.record(filesScanned: 0, progress: 0.1, at: 0)
        // 10 ms later — inside the 50 ms guard window; must not produce a
        // wildly inflated burst rate.
        estimator.record(filesScanned: 5_000, progress: 0.9, at: 0.01)
        if let rate = estimator.filesPerSecond {
            XCTAssertLessThan(rate, 100_000, "Burst sample must not explode the smoothed rate")
        }
    }
}
