import XCTest
@testable import kWise

final class ScanProgressTests: XCTestCase {
    func test_initialState_isIdle() {
        let progress = ScanProgress()
        XCTAssertEqual(progress.state, .idle)
    }

    func test_stateTransitions() {
        var progress = ScanProgress()
        progress.state = .scanning
        XCTAssertEqual(progress.state, .scanning)

        progress.state = .analysing
        XCTAssertEqual(progress.state, .analysing)

        progress.state = .completed
        XCTAssertEqual(progress.state, .completed)
    }

    func test_cancelled() {
        var progress = ScanProgress()
        progress.state = .cancelled
        XCTAssertEqual(progress.state, .cancelled)
    }

    func test_failed() {
        var progress = ScanProgress()
        progress.state = .failed("Test error")
        XCTAssertEqual(progress.state, .failed("Test error"))
    }

    func test_filesDiscovered_defaultsToZero() {
        let progress = ScanProgress()
        XCTAssertEqual(progress.filesDiscovered, 0)
    }

    func test_totalBytes_defaultsToZero() {
        let progress = ScanProgress()
        XCTAssertEqual(progress.totalBytes, 0)
    }
}

final class ScanProgressMathTests: XCTestCase {
    private func row(id: Int, status: ScanItemStatus) -> CategoryProgress {
        CategoryProgress(id: id, title: "\(id)", status: status,
                         subCategories: [], filesFound: 0, totalSize: 0)
    }

    func testCompletionEmptyProgressIsZero() {
        XCTAssertEqual(
            ScanProgressMath.completionFraction(categoryProgress: [], stats: ScanStats()),
            0
        )
    }

    func testCompletionAllDoneIsOne() {
        let rows = [row(id: 1, status: .completed), row(id: 2, status: .completed)]
        XCTAssertEqual(
            ScanProgressMath.completionFraction(categoryProgress: rows, stats: ScanStats()),
            1.0,
            "all categories done must hit exactly 100% so the ring never wedges short"
        )
    }

    func testCompletionBlendsStatsAndInflight() {
        let rows = [row(id: 1, status: .completed), row(id: 2, status: .scanning)]
        let stats = ScanStats(discoveredSize: 0, fileCount: 5000, elapsed: 100, filesPerSecond: 50)
        let fraction = ScanProgressMath.completionFraction(categoryProgress: rows, stats: stats)
        XCTAssertGreaterThan(fraction, 0.3)
        XCTAssertLessThan(fraction, 1.0)
    }

    func testCompletionNeverExceedsOne() {
        let rows = [row(id: 1, status: .completed)]
        let stats = ScanStats(discoveredSize: 0, fileCount: 100_000, elapsed: 1, filesPerSecond: 1000)
        XCTAssertLessThanOrEqual(
            ScanProgressMath.completionFraction(categoryProgress: rows, stats: stats),
            1.0
        )
    }

    func testETAEarlyFractionReturnsNil() {
        XCTAssertNil(
            ScanProgressMath.estimatedRemainingSeconds(categoryProgress: [], stats: ScanStats())
        )
    }

    func testETAStallReturnsNil() {
        let rows = [row(id: 1, status: .completed), row(id: 2, status: .pending)]
        XCTAssertNil(
            ScanProgressMath.estimatedRemainingSeconds(
                categoryProgress: rows,
                stats: ScanStats(discoveredSize: 0, fileCount: 0, elapsed: 10, filesPerSecond: 0)
            ),
            "a stalled scan (0 files/sec) must not show a fake ETA"
        )
    }

    func testETAComputesRemaining() {
        let rows = [row(id: 1, status: .completed), row(id: 2, status: .scanning)]
        let stats = ScanStats(discoveredSize: 0, fileCount: 100, elapsed: 10, filesPerSecond: 10)
        let eta = try! XCTUnwrap(
            ScanProgressMath.estimatedRemainingSeconds(categoryProgress: rows, stats: stats)
        )
        XCTAssertGreaterThan(eta, 0)
    }

    func testFormatClock() {
        XCTAssertEqual(ScanProgressMath.formatClock(42), "0:42")
        XCTAssertEqual(ScanProgressMath.formatClock(65), "1:05")
        XCTAssertEqual(ScanProgressMath.formatClock(3600), "1:00:00")
    }
}
