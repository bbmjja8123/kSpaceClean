import XCTest
import Combine
import MetricsKit
@testable import kWatch

@MainActor
final class DashboardViewModelTests: XCTestCase {
    private var appState: AppState!
    private var purchaseState: PurchaseState!

    override func setUp() {
        super.setUp()
        appState = AppState()
        purchaseState = PurchaseState()
    }

    // MARK: - Initial state

    func testInitialStateBuildsAllEightCards() {
        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        XCTAssertEqual(vm.cards.count, 8)
        XCTAssertFalse(vm.showOnboardingBanner)
    }

    func testInitialStateShowsOnboardingBannerWhenNotCompleted() {
        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: false
        )
        XCTAssertTrue(vm.showOnboardingBanner)
    }

    func testInitialCardsAreInMetricKindOrder() {
        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        let kinds = vm.cards.map(\.kind)
        XCTAssertEqual(kinds, MetricKind.allCases)
    }

    func testInitialCardsShowWaitingState() {
        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        for card in vm.cards {
            XCTAssertTrue(card.isUnavailable)
            XCTAssertEqual(card.subtitle, "Waiting for data")
        }
    }

    // MARK: - Snapshot updates

    func testSnapshotBuildsCardsForEveryMetricKind() {
        let snapshot = MetricSnapshot(
            timestamp: Date(),
            values: [
                .cpu: .percentage(72),
                .memory: .percentage(85),
                .disk: .percentage(44),
                .network: .bytesPerSecond(1_024_000),
                .temperature: .degreesCelsius(68),
                .fan: .revolutionsPerMinute(2200),
                .battery: .percentage(91),
                .gpu: .degreesCelsius(58)
            ],
            availability: [
                .temperature: .available,
                .fan: .available,
                .battery: .available,
                .gpu: .available
            ]
        )

        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        appState.update(snapshot: snapshot)

        XCTAssertEqual(vm.cards.count, 8)

        // CPU is free → not locked, displays value.
        let cpuCard = vm.cards.first { $0.kind == .cpu }!
        XCTAssertEqual(cpuCard.displayValue, "72%")
        XCTAssertFalse(cpuCard.isLocked)

        // Temperature is Pro → locked for free user.
        let tempCard = vm.cards.first { $0.kind == .temperature }!
        XCTAssertEqual(tempCard.displayValue, "68°C")
        XCTAssertTrue(tempCard.isLocked)
    }

    func testSnapshotWithMissingValuesDefaultsToUnavailable() {
        let partial = MetricSnapshot(
            timestamp: Date(),
            values: [.cpu: .percentage(50)],
            availability: [:]
        )

        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        appState.update(snapshot: partial)

        let missing = vm.cards.first { $0.kind == .memory }!
        XCTAssertEqual(missing.displayValue, "N/A")
    }

    // MARK: - Pro entitlement

    func testProEntitlementUnlocksCards() {
        let snapshot = MetricSnapshot(
            timestamp: Date(),
            values: [
                .temperature: .degreesCelsius(70),
                .fan: .revolutionsPerMinute(2000),
                .battery: .percentage(80)
            ],
            availability: [
                .temperature: .available,
                .fan: .available,
                .battery: .available
            ]
        )

        // Start as Pro — cards should be unlocked from the start.
        purchaseState.update(isPro: true)
        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        appState.update(snapshot: snapshot)

        XCTAssertFalse(vm.cards.first { $0.kind == .temperature }!.isLocked)
        XCTAssertEqual(vm.cards.first { $0.kind == .temperature }!.subtitle, "System Temperature")
    }

    func testDowngradeLocksProCards() {
        let snapshot = MetricSnapshot(
            timestamp: Date(),
            values: [.temperature: .degreesCelsius(70)],
            availability: [.temperature: .available]
        )

        // Start as Pro — card should be unlocked.
        purchaseState.update(isPro: true)
        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        appState.update(snapshot: snapshot)

        XCTAssertFalse(vm.cards.first { $0.kind == .temperature }!.isLocked)

        // Downgrade — create a new ViewModel with free state.
        let freePurchaseState = PurchaseState()
        let vm2 = DashboardViewModel(
            appState: appState,
            purchaseState: freePurchaseState,
            onboardingCompleted: true
        )
        appState.update(snapshot: snapshot)

        // Now locked.
        XCTAssertTrue(vm2.cards.first { $0.kind == .temperature }!.isLocked)
    }

    // MARK: - Selection

    func testSelectingCardUpdatesSelectedKind() {
        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        XCTAssertNil(vm.selectedKind)

        vm.selectedKind = .cpu
        XCTAssertEqual(vm.selectedKind, .cpu)
    }

    func testDismissOnboardingBanner() {
        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: false
        )
        XCTAssertTrue(vm.showOnboardingBanner)

        vm.dismissOnboardingBanner()
        XCTAssertFalse(vm.showOnboardingBanner)
    }

    // MARK: - Card identity

    func testCardsHaveUniqueIdentifiers() {
        let snapshot = MetricSnapshot(
            timestamp: Date(),
            values: [
                .cpu: .percentage(10),
                .memory: .percentage(20),
                .disk: .percentage(30),
                .network: .bytesPerSecond(100),
                .temperature: .degreesCelsius(40),
                .fan: .revolutionsPerMinute(1000),
                .battery: .percentage(50)
            ],
            availability: [
                .temperature: .available,
                .fan: .available,
                .battery: .available
            ]
        )

        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        appState.update(snapshot: snapshot)

        let ids = vm.cards.map(\.id)
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count)
    }

    // MARK: - Snapshot forwarding

    func testLatestSnapshotMirrorsAppState() {
        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        XCTAssertNil(vm.latestSnapshot)

        let snapshot = MetricSnapshot(timestamp: Date(), values: [.cpu: .percentage(50)], availability: [:])
        appState.update(snapshot: snapshot)

        XCTAssertEqual(vm.latestSnapshot, snapshot)
    }

    // MARK: - Monitoring state

    func testIsMonitoringMirrorsAppState() {
        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        XCTAssertFalse(vm.isMonitoring)

        appState.setMonitoring(true)
        XCTAssertTrue(vm.isMonitoring)

        appState.setMonitoring(false)
        XCTAssertFalse(vm.isMonitoring)
    }

    // MARK: - Navigation

    func testNavigateToHistoryUpdatesAppState() {
        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        vm.navigateToHistory()
        XCTAssertEqual(appState.navigation, .history)
    }

    func testNavigateToProcessesUpdatesAppState() {
        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        vm.navigateToProcesses()
        XCTAssertEqual(appState.navigation, .processes)
    }

    func testNavigateToAlertsUpdatesAppState() {
        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        vm.navigateToAlerts()
        XCTAssertEqual(appState.navigation, .alerts)
    }

    func testNavigationPropertyMirrorsAppState() {
        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        XCTAssertEqual(vm.navigation, .dashboard)

        appState.navigate(to: .processes)
        XCTAssertEqual(vm.navigation, .processes)
    }

    // MARK: - GPU Card

    func testGPUCardIsLockedForFreeUser() {
        let snapshot = MetricSnapshot(
            timestamp: Date(),
            values: [.gpu: .degreesCelsius(75)],
            availability: [.gpu: .available]
        )

        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        appState.update(snapshot: snapshot)

        let gpuCard = vm.cards.first { $0.kind == .gpu }!
        XCTAssertTrue(gpuCard.isLocked)
        XCTAssertFalse(gpuCard.isUnavailable)
        XCTAssertEqual(gpuCard.subtitle, "Pro Feature")
        XCTAssertEqual(gpuCard.icon, "lock.fill")
        XCTAssertEqual(gpuCard.cardColor, .gray)
    }

    func testGPUCardIsUnlockedForProUser() {
        let snapshot = MetricSnapshot(
            timestamp: Date(),
            values: [.gpu: .degreesCelsius(75)],
            availability: [.gpu: .available]
        )

        purchaseState.update(isPro: true)
        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        appState.update(snapshot: snapshot)

        let gpuCard = vm.cards.first { $0.kind == .gpu }!
        XCTAssertFalse(gpuCard.isLocked)
        XCTAssertEqual(gpuCard.subtitle, "GPU Temperature")
        XCTAssertEqual(gpuCard.icon, "display")
        XCTAssertEqual(gpuCard.cardColor, .purple)
        XCTAssertEqual(gpuCard.displayValue, "75°C")
    }

    func testGPUCardWithHardwareUnavailable() {
        let snapshot = MetricSnapshot(
            timestamp: Date(),
            values: [.gpu: .unavailable(.unsupported("No GPU sensor"))],
            availability: [.gpu: .unsupported(reason: "No GPU sensor")]
        )

        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        appState.update(snapshot: snapshot)

        let gpuCard = vm.cards.first { $0.kind == .gpu }!
        XCTAssertTrue(gpuCard.isUnavailable)
        XCTAssertFalse(gpuCard.isLocked)
        XCTAssertEqual(gpuCard.subtitle, "No GPU sensor")
        XCTAssertEqual(gpuCard.icon, "questionmark.circle")
        XCTAssertEqual(gpuCard.cardColor, .gray)
    }

    func testGPUCardDisplaysTemperatureValueWhenPro() {
        let snapshot = MetricSnapshot(
            timestamp: Date(),
            values: [.gpu: .degreesCelsius(92.3)],
            availability: [.gpu: .available]
        )

        purchaseState.update(isPro: true)
        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        appState.update(snapshot: snapshot)

        let gpuCard = vm.cards.first { $0.kind == .gpu }!
        XCTAssertEqual(gpuCard.displayValue, "92°C")
        XCTAssertFalse(gpuCard.isLocked)
    }

    func testNavigateToDashboardUpdatesAppState() {
        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        // Navigate away first
        vm.navigateToProcesses()
        XCTAssertEqual(appState.navigation, .processes)

        vm.navigateToDashboard()
        XCTAssertEqual(appState.navigation, .dashboard)
    }
}
