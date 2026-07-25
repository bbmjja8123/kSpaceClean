import XCTest
@testable import MetricsKit

final class MetricModelsTests: XCTestCase {
    func testSnapshotStoresValuesByKind() {
        let snapshot = MetricSnapshot(
            timestamp: Date(timeIntervalSince1970: 10),
            values: [.cpu: .percentage(42), .memory: .percentage(61)])
        XCTAssertEqual(snapshot.values[.cpu], .percentage(42))
        XCTAssertEqual(snapshot.values[.memory], .percentage(61))
    }

    func testMetricValueEqualityIsStableForPersistenceAndViews() {
        XCTAssertEqual(MetricValue.bytes(1024), MetricValue.bytes(1024))
        XCTAssertNotEqual(MetricValue.percentage(1), MetricValue.percentage(2))
    }
}
