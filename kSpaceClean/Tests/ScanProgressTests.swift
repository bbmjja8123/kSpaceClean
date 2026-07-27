import XCTest
@testable import kSpaceClean

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
