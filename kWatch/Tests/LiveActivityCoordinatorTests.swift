import XCTest
@testable import kWatch

#if canImport(ActivityKit)

/// Smoke tests for `LiveActivityCoordinator`. The ActivityKit code path is
/// gated by `#if canImport(ActivityKit)` and `@available(macOS 14.0, *)`,
/// so on the macOS 13 SDK used by CI these tests are skipped entirely.
/// The actual `Activity.request` path is exercised on macOS 14+ hardware.
final class LiveActivityCoordinatorTests: XCTestCase {

    func testTrendCasesAreDefined() {
        let up = LiveActivityCoordinator.Trend.up
        let down = LiveActivityCoordinator.Trend.down
        let flat = LiveActivityCoordinator.Trend.flat
        XCTAssertEqual(up.rawValue, "up")
        XCTAssertEqual(down.rawValue, "down")
        XCTAssertEqual(flat.rawValue, "flat")
    }
}

#endif
