import XCTest
import MetricsKit
@testable import kWatch

/// Tests for `InMemoryAlertRepository` — the in-process backend used by
/// previews and tests, and the `AlertRepository` protocol that the Core
/// Data-backed production repository also implements.
final class AlertRepositoryTests: XCTestCase {

    private func makeAlert(
        kind: MetricKind = .cpu,
        threshold: Double = 80,
        cooldownSeconds: Int = 60
    ) -> MetricAlert {
        MetricAlert(kind: kind, op: .above, threshold: threshold, cooldownSeconds: cooldownSeconds)
    }

    func testUpsertThenAllReturnsSortedByKind() throws {
        let repo = InMemoryAlertRepository()
        try repo.upsert(makeAlert(kind: .memory))
        try repo.upsert(makeAlert(kind: .cpu))
        try repo.upsert(makeAlert(kind: .disk))

        let all = try repo.all()
        XCTAssertEqual(all.map(\.kind), [.cpu, .disk, .memory])
    }

    func testUpsertReplacesExistingAlertByID() throws {
        let repo = InMemoryAlertRepository()
        let id = UUID()
        try repo.upsert(MetricAlert(id: id, kind: .cpu, op: .above, threshold: 50))
        try repo.upsert(MetricAlert(id: id, kind: .cpu, op: .above, threshold: 90))

        let all = try repo.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.threshold, 90)
    }

    func testDeleteRemovesAlertByID() throws {
        let repo = InMemoryAlertRepository()
        let alert = makeAlert()
        try repo.upsert(alert)
        try repo.delete(id: alert.id)
        XCTAssertTrue(try repo.all().isEmpty)
    }

    func testDeleteUnknownIDIsNoOp() throws {
        let repo = InMemoryAlertRepository()
        try repo.delete(id: UUID())
        XCTAssertTrue(try repo.all().isEmpty)
    }

    func testRecordTriggeredUpdatesLastTriggeredAt() throws {
        let repo = InMemoryAlertRepository()
        let alert = makeAlert(cooldownSeconds: 60)
        try repo.upsert(alert)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try repo.recordTriggered(id: alert.id, at: now)
        let updated = try repo.all().first
        XCTAssertEqual(updated?.lastTriggeredAt, now)
    }

    func testRecordTriggeredUnknownIDIsNoOp() throws {
        let repo = InMemoryAlertRepository()
        try repo.recordTriggered(id: UUID(), at: Date())
        XCTAssertTrue(try repo.all().isEmpty)
    }

    func testAlertOperatorBelowRoundTrips() {
        let alert = MetricAlert(kind: .memory, op: .below, threshold: 20)
        XCTAssertEqual(alert.op, .below)
    }
}