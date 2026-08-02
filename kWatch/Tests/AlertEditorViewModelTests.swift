import XCTest
import MetricsKit
@testable import kWatch

/// Tests for the per-metric alert editor's evaluation rules: the 5-minute
/// cooldown floor enforced by `AlertEvaluator`.
final class AlertEditorViewModelTests: XCTestCase {

    func testFiveMinuteCooldownRespected() {
        let now = Date()
        XCTAssertTrue(AlertEvaluator.shouldFire(kind: .cpu, lastFireTime: nil, now: now))
        XCTAssertFalse(AlertEvaluator.shouldFire(
            kind: .cpu,
            lastFireTime: now.addingTimeInterval(-60),
            now: now
        ))
        XCTAssertTrue(AlertEvaluator.shouldFire(
            kind: .cpu,
            lastFireTime: now.addingTimeInterval(-301),
            now: now
        ))
    }

    func testEvaluateEnforcesCooldownFloor() {
        let now = Date()

        // Configured cooldown of 60s and last fired 60s ago: the 300s floor
        // still suppresses the alert even though the 60s cooldown elapsed.
        let suppressed = MetricAlert(
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 60,
            lastTriggeredAt: now.addingTimeInterval(-60)
        )
        let suppressedResult = AlertEvaluator.evaluate(
            snapshot: MetricSnapshot(timestamp: now, values: [.cpu: .percentage(95)]),
            alerts: [suppressed],
            now: now
        )
        XCTAssertTrue(suppressedResult.isEmpty)

        // 301s since last fire: the floor has passed and the configured 60s
        // cooldown is well past, so the alert fires.
        let ready = MetricAlert(
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 60,
            lastTriggeredAt: now.addingTimeInterval(-301)
        )
        let readyResult = AlertEvaluator.evaluate(
            snapshot: MetricSnapshot(timestamp: now, values: [.cpu: .percentage(95)]),
            alerts: [ready],
            now: now
        )
        XCTAssertEqual(readyResult.count, 1)
    }

    func testUserCooldownLongerThanFloorIsHonored() {
        let now = Date()

        // The 300s floor has passed (301s), but the user-configured 600s
        // cooldown is still active, so the alert stays suppressed.
        let alert = MetricAlert(
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 600,
            lastTriggeredAt: now.addingTimeInterval(-301)
        )
        let result = AlertEvaluator.evaluate(
            snapshot: MetricSnapshot(timestamp: now, values: [.cpu: .percentage(95)]),
            alerts: [alert],
            now: now
        )
        XCTAssertTrue(result.isEmpty)
    }
}
