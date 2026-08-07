import XCTest
import UserNotifications
import MetricsKit
@testable import kWatch

// MARK: - NotificationSchedulerTests

final class NotificationSchedulerTests: XCTestCase {

    // MARK: - Permission-guarded scheduling

    func testDoesNotScheduleWhenPermissionUndetermined() async {
        let scheduler = NotificationScheduler(overriddenAuthStatus: .notDetermined)
        let box = SendableBox<[ScheduledNotificationInfo]>([])
        await scheduler.setOnSchedule { box.value.append($0) }

        let alert = MetricAlert(
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 300
        )
        await scheduler.schedule(alert: alert, value: .percentage(95))

        XCTAssertTrue(box.value.isEmpty)
    }

    func testDoesNotScheduleWhenPermissionDenied() async {
        let scheduler = NotificationScheduler(overriddenAuthStatus: .denied)
        let box = SendableBox<[ScheduledNotificationInfo]>([])
        await scheduler.setOnSchedule { box.value.append($0) }

        let alert = MetricAlert(
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 300
        )
        await scheduler.schedule(alert: alert, value: .percentage(95))

        XCTAssertTrue(box.value.isEmpty)
    }

    func testSchedulesWhenAuthorized() async {
        let scheduler = NotificationScheduler(overriddenAuthStatus: .authorized)
        let box = SendableBox<[ScheduledNotificationInfo]>([])
        await scheduler.setOnSchedule { box.value.append($0) }

        let alert = MetricAlert(
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 300
        )
        await scheduler.schedule(alert: alert, value: .percentage(95))

        XCTAssertEqual(box.value.count, 1)
        XCTAssertEqual(box.value.first?.identifier, alert.id.uuidString)
    }

    func testSchedulesWhenProvisional() async {
        let scheduler = NotificationScheduler(overriddenAuthStatus: .provisional)
        let box = SendableBox<[ScheduledNotificationInfo]>([])
        await scheduler.setOnSchedule { box.value.append($0) }

        let alert = MetricAlert(
            kind: .memory, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 300
        )
        await scheduler.schedule(alert: alert, value: .percentage(90))

        XCTAssertEqual(box.value.count, 1)
    }

    // MARK: - Content formatting

    func testScheduledContentContainsAlertInfo() async {
        let scheduler = NotificationScheduler(overriddenAuthStatus: .authorized)
        let box = SendableBox<ScheduledNotificationInfo?>(nil)
        await scheduler.setOnSchedule { box.value = $0 }

        let alert = MetricAlert(
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 300
        )
        await scheduler.schedule(alert: alert, value: .percentage(95))

        guard let info = box.value else {
            XCTFail("Expected a notification to be scheduled")
            return
        }

        XCTAssertTrue(info.body.contains("Cpu"))
        XCTAssertTrue(info.body.contains("above"))
        XCTAssertTrue(info.body.contains("80%"))
        XCTAssertTrue(info.body.contains("95%"))
    }

    func testScheduledContentForBelowOperator() async {
        let scheduler = NotificationScheduler(overriddenAuthStatus: .authorized)
        let box = SendableBox<ScheduledNotificationInfo?>(nil)
        await scheduler.setOnSchedule { box.value = $0 }

        let alert = MetricAlert(
            kind: .memory, op: .below, threshold: 20,
            isEnabled: true, cooldownSeconds: 300
        )
        await scheduler.schedule(alert: alert, value: .percentage(15))

        guard let info = box.value else {
            XCTFail("Expected a notification to be scheduled")
            return
        }

        XCTAssertTrue(info.body.contains("Memory"))
        XCTAssertTrue(info.body.contains("below"))
        XCTAssertTrue(info.body.contains("20%"))
        XCTAssertTrue(info.body.contains("15%"))
    }

    func testScheduledContentForTemperature() async {
        let scheduler = NotificationScheduler(overriddenAuthStatus: .authorized)
        let box = SendableBox<ScheduledNotificationInfo?>(nil)
        await scheduler.setOnSchedule { box.value = $0 }

        let alert = MetricAlert(
            kind: .temperature, op: .above, threshold: 85,
            isEnabled: true, cooldownSeconds: 300
        )
        await scheduler.schedule(alert: alert, value: .degreesCelsius(92))

        guard let info = box.value else {
            XCTFail("Expected a notification to be scheduled")
            return
        }

        XCTAssertTrue(info.body.contains("above"))
        XCTAssertTrue(info.body.contains("92"))
    }

    // MARK: - Title

    func testNotificationTitleIsKWatchAlert() async {
        let scheduler = NotificationScheduler(overriddenAuthStatus: .authorized)
        let box = SendableBox<ScheduledNotificationInfo?>(nil)
        await scheduler.setOnSchedule { box.value = $0 }

        let alert = MetricAlert(
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 300
        )
        await scheduler.schedule(alert: alert, value: .percentage(95))

        XCTAssertEqual(box.value?.title, "kWatch Alert")
    }

    // MARK: - Remove pending

    func testRemovePendingCallsCenter() async {
        // We cannot easily verify the removal call without stubbing the center,
        // but the method should not throw or trap.
        let scheduler = NotificationScheduler(overriddenAuthStatus: .authorized)
        let alert = MetricAlert(
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 300
        )
        // Should not throw
        await scheduler.removePending(alertID: alert.id)
    }

    // MARK: - No-op for unavailable values

    func testUnavailableValueStillSchedules() async {
        // Scheduling depends on permission, not on the value.
        let scheduler = NotificationScheduler(overriddenAuthStatus: .authorized)
        let box = SendableBox<[ScheduledNotificationInfo]>([])
        await scheduler.setOnSchedule { box.value.append($0) }

        let alert = MetricAlert(
            kind: .temperature, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 300
        )
        await scheduler.schedule(alert: alert, value: .unavailable(.unsupported("test")))

        // The scheduler does not check value availability — that is the
        // evaluator's responsibility.  It will still schedule.
        XCTAssertEqual(box.value.count, 1)
    }
}
