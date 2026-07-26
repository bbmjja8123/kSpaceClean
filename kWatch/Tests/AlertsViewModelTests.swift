import XCTest
import UserNotifications
import MetricsKit
@testable import kWatch

// MARK: - AlertsViewModelTests

@MainActor
final class AlertsViewModelTests: XCTestCase {

    // MARK: - Empty state

    func testEmptyByDefault() {
        let repo = InMemoryAlertRepository()
        let vm = makeVM(repo: repo)
        vm.refresh()
        XCTAssertTrue(vm.alerts.isEmpty)
    }

    // MARK: - CRUD

    func testAddAlertAppearsInList() throws {
        let repo = InMemoryAlertRepository()
        let vm = makeVM(repo: repo)

        let alert = MetricAlert(
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 300
        )
        try repo.upsert(alert)
        vm.refresh()

        XCTAssertEqual(vm.alerts.count, 1)
        XCTAssertEqual(vm.alerts.first?.kind, .cpu)
        XCTAssertEqual(vm.alerts.first?.threshold, 80)
        XCTAssertEqual(vm.alerts.first?.cooldownSeconds, 300)
    }

    func testEditUpdatesExistingAlert() throws {
        let repo = InMemoryAlertRepository()
        let vm = makeVM(repo: repo)
        let alert = MetricAlert(
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 300
        )
        try repo.upsert(alert)
        vm.refresh()

        let updated = MetricAlert(
            id: alert.id,
            kind: .memory,
            op: .below,
            threshold: 50,
            isEnabled: alert.isEnabled,
            cooldownSeconds: 120,
            lastTriggeredAt: alert.lastTriggeredAt
        )
        vm.save(updated)

        XCTAssertEqual(vm.alerts.count, 1)
        XCTAssertEqual(vm.alerts.first?.kind, .memory)
        XCTAssertEqual(vm.alerts.first?.threshold, 50)
        XCTAssertEqual(vm.alerts.first?.cooldownSeconds, 120)
    }

    func testDeleteRemovesAlert() throws {
        let repo = InMemoryAlertRepository()
        let vm = makeVM(repo: repo)
        let alert = MetricAlert(
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 300
        )
        try repo.upsert(alert)
        vm.refresh()
        XCTAssertEqual(vm.alerts.count, 1)

        vm.delete(alert)
        XCTAssertTrue(vm.alerts.isEmpty)
    }

    // MARK: - Toggle enabled state

    func testToggleFlipsEnabledState() throws {
        let repo = InMemoryAlertRepository()
        let vm = makeVM(repo: repo)
        let alert = MetricAlert(
            id: UUID(),
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 300
        )
        try repo.upsert(alert)
        vm.refresh()
        XCTAssertEqual(vm.alerts.first?.isEnabled, true)

        vm.toggle(alert)
        vm.refresh()
        XCTAssertEqual(vm.alerts.first?.isEnabled, false)

        // Toggle back
        let toggledBack = MetricAlert(
            id: alert.id,
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: false, cooldownSeconds: 300
        )
        vm.toggle(toggledBack)
        vm.refresh()
        XCTAssertEqual(vm.alerts.first?.isEnabled, true)
    }

    // MARK: - Editor sheet

    func testBeginAddSetsEditingAlert() {
        let repo = InMemoryAlertRepository()
        let vm = makeVM(repo: repo)
        vm.beginAdd()

        XCTAssertNotNil(vm.editingAlert)
        XCTAssertTrue(vm.isPresentingEditor)
        XCTAssertTrue(vm.isEditingNewAlert)
    }

    func testBeginEditSelectsExistingAlert() throws {
        let repo = InMemoryAlertRepository()
        let vm = makeVM(repo: repo)
        let alert = MetricAlert(
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 300
        )
        try repo.upsert(alert)
        vm.refresh()

        vm.beginEdit(alert)
        XCTAssertEqual(vm.editingAlert?.id, alert.id)
        XCTAssertTrue(vm.isPresentingEditor)
        XCTAssertFalse(vm.isEditingNewAlert)
    }

    // MARK: - Default alerts

    func testEnsureDefaultsPopulatesThreeAlerts() throws {
        let repo = InMemoryAlertRepository()
        let vm = makeVM(repo: repo)
        vm.refresh()
        XCTAssertTrue(vm.alerts.isEmpty)

        vm.ensureDefaults()
        vm.refresh()
        XCTAssertEqual(vm.alerts.count, 3)

        let kinds = vm.alerts.map(\.kind)
        XCTAssertTrue(kinds.contains(.cpu))
        XCTAssertTrue(kinds.contains(.memory))
        XCTAssertTrue(kinds.contains(.disk))
    }

    func testEnsureDefaultsDoesNotDuplicate() throws {
        let repo = InMemoryAlertRepository()
        let vm = makeVM(repo: repo)
        let alert = MetricAlert(
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 300
        )
        try repo.upsert(alert)
        vm.refresh()

        vm.ensureDefaults()
        vm.refresh()
        XCTAssertEqual(vm.alerts.count, 1)
    }

    // MARK: - AlertEvaluator integration: cooldown

    func testCooldownPreventsRepeatedFiring() throws {
        let repo = InMemoryAlertRepository()
        let vm = makeVM(repo: repo)

        let alert = MetricAlert(
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 60,
            lastTriggeredAt: Date(timeIntervalSince1970: 10)
        )
        try repo.upsert(alert)
        vm.refresh()

        // Cooldown still active (30 < 10 + 60)
        let earlySnapshot = MetricSnapshot(
            timestamp: Date(timeIntervalSince1970: 30),
            values: [.cpu: .percentage(95)]
        )
        let earlyResult = AlertEvaluator.evaluate(
            snapshot: earlySnapshot,
            alerts: vm.alerts,
            now: Date(timeIntervalSince1970: 30)
        )
        XCTAssertTrue(earlyResult.isEmpty)

        // Cooldown expired (80 >= 10 + 60)
        let lateSnapshot = MetricSnapshot(
            timestamp: Date(timeIntervalSince1970: 80),
            values: [.cpu: .percentage(95)]
        )
        let lateResult = AlertEvaluator.evaluate(
            snapshot: lateSnapshot,
            alerts: vm.alerts,
            now: Date(timeIntervalSince1970: 80)
        )
        XCTAssertEqual(lateResult.count, 1)
    }

    // MARK: - AlertEvaluator integration: threshold matching

    func testAboveThresholdTriggers() {
        let alert = MetricAlert(
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 300
        )
        let snapshot = MetricSnapshot(
            timestamp: Date(),
            values: [.cpu: .percentage(95)]
        )
        let result = AlertEvaluator.evaluate(snapshot: snapshot, alerts: [alert])
        XCTAssertEqual(result.count, 1)
    }

    func testBelowThresholdDoesNotTriggerAboveAlert() {
        let alert = MetricAlert(
            kind: .cpu, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 300
        )
        let snapshot = MetricSnapshot(
            timestamp: Date(),
            values: [.cpu: .percentage(50)]
        )
        let result = AlertEvaluator.evaluate(snapshot: snapshot, alerts: [alert])
        XCTAssertTrue(result.isEmpty)
    }

    func testUnavailableMetricNeverTriggers() {
        let alert = MetricAlert(
            kind: .temperature, op: .above, threshold: 80,
            isEnabled: true, cooldownSeconds: 300
        )
        let snapshot = MetricSnapshot(
            timestamp: Date(),
            values: [.temperature: .unavailable(.unsupported("no SMC"))]
        )
        let result = AlertEvaluator.evaluate(snapshot: snapshot, alerts: [alert])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Helpers

    private func makeVM(repo: AlertRepositoryProtocol) -> AlertsViewModel {
        AlertsViewModel(
            repository: repo,
            scheduler: NotificationScheduler(
                overriddenAuthStatus: .denied
            ),
            appState: AppState(),
            purchaseState: PurchaseState()
        )
    }
}
