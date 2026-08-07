import XCTest
import MetricsKit
@testable import kWatch

@MainActor
final class AppCoordinatorTests: XCTestCase {
    func testCoordinatorStartsAndStopsItsTaskGroup() {
        let container = TestAppContainer(cpu: .percentage(10))
        let coordinator = AppCoordinator(container: container)

        coordinator.start()
        XCTAssertTrue(coordinator.isRunning)
        XCTAssertTrue(container.appState.isMonitoring)

        coordinator.stop()
        XCTAssertFalse(coordinator.isRunning)
        XCTAssertFalse(container.appState.isMonitoring)
    }

    func testCoordinatorProcessesSnapshotsAndPersistsLatest() async throws {
        let container = TestAppContainer(cpu: .percentage(37))
        let coordinator = AppCoordinator(container: container)
        coordinator.start()
        defer { coordinator.stop() }

        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(container.metricsRepository.latest?.values[.cpu], .percentage(37))
    }

    func testCoordinatorWritesSharedSnapshotOnEachTick() async throws {
        let container = TestAppContainer(cpu: .percentage(50), memory: .percentage(60))
        let coordinator = AppCoordinator(container: container)
        coordinator.start()
        defer { coordinator.stop() }

        try await Task.sleep(for: .milliseconds(50))
        let shared = try container.snapshotWriter.read()
        XCTAssertNotNil(shared)
        XCTAssertEqual(shared?.cpuPercent, 50)
        XCTAssertEqual(shared?.memoryPercent, 60)
    }

    func testCoordinatorSchedulesNotificationWhenAlertAuthorized() async throws {
        let container = TestAppContainer(
            cpu: .percentage(95),
            notificationScheduler: NotificationScheduler(overriddenAuthStatus: .authorized)
        )
        let alert = MetricAlert(
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 60
        )
        try container.alertRepository.upsert(alert)

        let box = SendableBox<[ScheduledNotificationInfo]>([])
        let scheduler = container.notificationScheduler as! NotificationScheduler
        await scheduler.setOnSchedule { box.value.append($0) }

        let coordinator = AppCoordinator(container: container)
        coordinator.start()
        defer { coordinator.stop() }

        try await Task.sleep(for: .milliseconds(80))

        let alerts = try container.alertRepository.all()
        XCTAssertNotNil(alerts.first?.lastTriggeredAt, "Alert should have triggered")
        XCTAssertFalse(box.value.isEmpty, "Scheduler should have been invoked")
        XCTAssertEqual(box.value.first?.identifier, alert.id.uuidString)
    }

    func testCoordinatorDoesNotScheduleWhenNotificationDenied() async throws {
        let container = TestAppContainer(
            cpu: .percentage(95),
            notificationScheduler: NotificationScheduler(overriddenAuthStatus: .denied)
        )
        let alert = MetricAlert(
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 60
        )
        try container.alertRepository.upsert(alert)

        let box = SendableBox<[ScheduledNotificationInfo]>([])
        let scheduler = container.notificationScheduler as! NotificationScheduler
        await scheduler.setOnSchedule { box.value.append($0) }

        let coordinator = AppCoordinator(container: container)
        coordinator.start()
        defer { coordinator.stop() }

        try await Task.sleep(for: .milliseconds(80))

        XCTAssertTrue(box.value.isEmpty, "Scheduler must not fire when permission is denied")
        // lastTriggeredAt is still updated so cooldown is honored once
        // the user later grants permission.
        let alerts = try container.alertRepository.all()
        XCTAssertNotNil(alerts.first?.lastTriggeredAt)
    }
}
