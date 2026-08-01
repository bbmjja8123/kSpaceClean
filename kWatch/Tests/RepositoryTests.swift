import XCTest
import CoreData
import MetricsKit
@testable import kWatch

final class RepositoryTests: XCTestCase {
    func testInMemoryHistoryFiltersByDateAndPurgesOldSamples() throws {
        let repository = InMemoryHistoryRepository()
        let early = MetricSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            values: [.cpu: .percentage(10)]
        )
        let late = MetricSnapshot(
            timestamp: Date(timeIntervalSince1970: 100),
            values: [.cpu: .percentage(90)]
        )

        try repository.append(early)
        try repository.append(late)

        XCTAssertEqual(
            try repository.samples(since: Date(timeIntervalSince1970: 50)).count,
            1
        )
        try repository.purge(olderThan: Date(timeIntervalSince1970: 50))
        XCTAssertEqual(try repository.samples(since: .distantPast).count, 1)
    }

    func testMetricsRepositoryRoundTripsLatestSnapshot() {
        let defaults = UserDefaults(suiteName: "kWatch.tests.\(UUID().uuidString)")!
        let repository = MetricsRepository(defaults: defaults)
        XCTAssertNil(repository.latest)

        let snapshot = MetricSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            values: [.cpu: .percentage(42)]
        )
        repository.saveLatest(snapshot)

        XCTAssertEqual(repository.latest?.values[.cpu], .percentage(42))
        let reread = MetricsRepository(defaults: defaults)
        XCTAssertEqual(reread.latest?.values[.cpu], .percentage(42))
    }

    func testAlertRepositoryUpsertsAndDeletes() throws {
        let repository = InMemoryAlertRepository()
        let alert = MetricAlert(
            kind: .cpu,
            op: .above,
            threshold: 80,
            cooldownSeconds: 60
        )

        try repository.upsert(alert)
        XCTAssertEqual(try repository.all().count, 1)
        try repository.delete(id: alert.id)
        XCTAssertEqual(try repository.all().count, 0)
    }

    func testAlertEvaluatorMatchesThresholdAndRespectsEnabled() {
        let alert = MetricAlert(
            kind: .cpu,
            op: .above,
            threshold: 80,
            isEnabled: true
        )
        let snapshot = MetricSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            values: [.cpu: .percentage(95)]
        )

        XCTAssertTrue(
            AlertEvaluator.evaluate(snapshot: snapshot, alerts: [alert])
                .contains(where: { $0.id == alert.id })
        )
        let disabled = MetricAlert(
            id: alert.id,
            kind: .cpu,
            op: .above,
            threshold: 80,
            isEnabled: false
        )
        XCTAssertFalse(
            AlertEvaluator.evaluate(snapshot: snapshot, alerts: [disabled])
                .contains(where: { $0.id == alert.id })
        )
    }

    func testHistoryRepositoryStoresNetworkRateWithoutHalving() throws {
        let stack = try CoreDataStack(inMemory: true)
        let repository = HistoryRepository(stack: stack)
        let snapshot = MetricSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            values: [.network: .bytesPerSecond(3_000)]
        )

        try repository.append(snapshot)

        let request = NSFetchRequest<MetricHistoryRecord>(entityName: "MetricHistoryRecord")
        let records = try stack.viewContext.fetch(request)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].networkReceiveBytesPerSecond, 3_000)
        XCTAssertEqual(records[0].networkSendBytesPerSecond, 0)

        let loaded = try repository.samples(since: .distantPast)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].values[.network], .bytesPerSecond(3_000))
    }
}
