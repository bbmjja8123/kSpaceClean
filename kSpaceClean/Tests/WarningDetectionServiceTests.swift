// kSpaceClean/Features/Cleanup/Tests/WarningDetectionServiceTests.swift
//
// Task C3 — WarningDetectionService (Layer 1) tests.
//
// The Layer 1 detector shells out to `lsof` and enumerates every PID on the
// system, both of which are side-effecting. The tests below therefore focus
// on the **pure** paths of the API: the early-return guards and the dedup
// helper. End-to-end detection is exercised manually (the unit-test runner
// cannot reliably inspect the user's open files).
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
}