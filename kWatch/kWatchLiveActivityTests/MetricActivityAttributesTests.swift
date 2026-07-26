import XCTest
@testable import kWatchLiveActivity

final class MetricActivityAttributesTests: XCTestCase {
    func testContentStateRoundTripsThroughJSON() throws {
        let state = MetricActivityAttributes.ContentState(
            value: 48,
            trend: .up,
            timestamp: Date(timeIntervalSince1970: 1),
            isAvailable: true,
            displayUnit: "%"
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(
            MetricActivityAttributes.ContentState.self,
            from: data
        )

        XCTAssertEqual(decoded, state)
    }

    func testAttributesRoundTrip() throws {
        let attributes = MetricActivityAttributes(
            kindRaw: "cpu",
            startedAt: Date(timeIntervalSince1970: 2),
            displayPreferenceRaw: "percentage"
        )
        let data = try JSONEncoder().encode(attributes)
        let decoded = try JSONDecoder().decode(
            MetricActivityAttributes.self,
            from: data
        )

        XCTAssertEqual(decoded, attributes)
    }

    func testTrendRawValues() {
        XCTAssertEqual(MetricActivityAttributes.ContentState.Trend.up.rawValue, "up")
        XCTAssertEqual(MetricActivityAttributes.ContentState.Trend.down.rawValue, "down")
        XCTAssertEqual(MetricActivityAttributes.ContentState.Trend.flat.rawValue, "flat")
    }

    func testContentStateHashableConformance() {
        let timestamp = Date(timeIntervalSince1970: 3)
        let first = MetricActivityAttributes.ContentState(
            value: 12,
            trend: .flat,
            timestamp: timestamp,
            isAvailable: true,
            displayUnit: "%"
        )
        let second = MetricActivityAttributes.ContentState(
            value: 12,
            trend: .flat,
            timestamp: timestamp,
            isAvailable: true,
            displayUnit: "%"
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.hashValue, second.hashValue)
    }
}
