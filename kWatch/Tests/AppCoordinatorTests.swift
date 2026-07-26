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
}
