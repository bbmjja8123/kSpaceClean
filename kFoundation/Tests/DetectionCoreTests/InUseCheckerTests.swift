import XCTest
@testable import DetectionCore

final class InUseCheckerTests: XCTestCase {
    private func file(_ path: String, modifiedAgo: TimeInterval = 3_600) -> FileItem {
        .mock(
            url: URL(fileURLWithPath: path),
            size: 100,
            modificationDate: Date(timeIntervalSinceNow: -modifiedAgo)
        )
    }

    // MARK: - Stubs

    private struct StubProvider: InUseChecking {
        var holders: [String: [InUseProcess]]?
        func processesHolding(_ paths: [String]) -> [String: [InUseProcess]]? {
            holders
        }
    }

    // MARK: - Classification

    func testHeldFileReportedInUse() async {
        let held = file("/tmp/a.bin")
        let free = file("/tmp/b.bin")
        let checker = InUseChecker(provider: StubProvider(holders: [
            "/tmp/a.bin": [InUseProcess(pid: 42, name: "Safari")],
        ]))
        let report = await checker.assess([held, free])
        XCTAssertTrue(report.likelyInUse.isEmpty, "Old files without holders are not flagged")
        XCTAssertEqual(report.inUse[held.id]?.processes.first?.name, "Safari")
        XCTAssertNil(report.inUse[free.id])
        XCTAssertFalse(report.checkUnavailable)
    }

    func testRecentlyModifiedFileFlaggedAsLikelyInUse() async {
        let fresh = file("/tmp/fresh.bin", modifiedAgo: 30)
        let checker = InUseChecker(provider: StubProvider(holders: [:]))
        let report = await checker.assess([fresh])
        XCTAssertTrue(report.inUse.isEmpty)
        XCTAssertEqual(report.likelyInUse.map(\.id), [fresh.id])
    }

    func testTempSuffixFileFlaggedAsLikelyInUse() async {
        let downloading = file("/tmp/movie.crdownload", modifiedAgo: 3_600)
        let checker = InUseChecker(provider: StubProvider(holders: [:]))
        let report = await checker.assess([downloading])
        XCTAssertEqual(report.likelyInUse.map(\.id), [downloading.id], "Temp-suffix files are flagged even when old")
    }

    func testUnavailableProviderDegradesToHeuristics() async {
        let fresh = file("/tmp/fresh.bin", modifiedAgo: 30)
        let old = file("/tmp/old.bin", modifiedAgo: 3_600)
        let checker = InUseChecker(provider: StubProvider(holders: nil))
        let report = await checker.assess([fresh, old])
        XCTAssertTrue(report.checkUnavailable, "Nil provider output means the check could not run")
        XCTAssertEqual(report.likelyInUse.map(\.id), [fresh.id], "Heuristic coverage only")
        XCTAssertTrue(report.inUse.isEmpty)
    }

    func testEmptyInputShortCircuits() async {
        let checker = InUseChecker(provider: StubProvider(holders: nil))
        let report = await checker.assess([])
        XCTAssertFalse(report.checkUnavailable, "Nothing to check → no unavailable notice")
        XCTAssertTrue(report.isEmpty)
    }

    // MARK: - Heuristics

    func testHeuristicTempSuffixes() {
        let item = file("/tmp/x.part")
        XCTAssertTrue(InUseHeuristics.isLikelyInUse(item))
    }
}
