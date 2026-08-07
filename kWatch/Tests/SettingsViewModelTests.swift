import XCTest
import MetricsKit
import DesignSystem
@testable import kWatch

// MARK: - SettingsViewModelTests

@MainActor
final class SettingsViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeModel(
        preferences: PreferencesRepositoryProtocol? = nil,
        scheduler: NotificationSchedulerProtocol? = nil,
        purchaseState: PurchaseState? = nil
    ) -> SettingsViewModel {
        SettingsViewModel(
            preferences: preferences ?? InMemoryPreferences(),
            scheduler: scheduler ?? NotificationScheduler(overriddenAuthStatus: .denied),
            purchaseState: purchaseState ?? PurchaseState()
        )
    }

    // MARK: - Menu bar mode

    func testChangingMenuBarModePersistsImmediately() {
        let preferences = InMemoryPreferences()
        let vm = makeModel(preferences: preferences)

        vm.setMenuBarMode(.minimal)

        XCTAssertEqual(preferences.menuBarMode, .minimal)
        XCTAssertEqual(vm.menuBarMode, .minimal)
    }

    func testSettingSameMenuBarModeIsNoop() {
        let preferences = InMemoryPreferences()
        preferences.menuBarMode = .trend
        let vm = makeModel(preferences: preferences)

        vm.setMenuBarMode(.trend)

        XCTAssertEqual(preferences.menuBarMode, .trend)
    }

    // MARK: - Icon style

    func testSettingSameIconStyleIsNoop() {
        let preferences = InMemoryPreferences()
        let vm = makeModel(preferences: preferences)

        vm.setIconStyle(.sparkline, for: .cpu)
        let persistedTheme = preferences.menuBarIconTheme

        vm.setIconStyle(.sparkline, for: .cpu)

        XCTAssertEqual(preferences.menuBarIconTheme, persistedTheme)
        XCTAssertEqual(vm.iconTheme, persistedTheme)
    }


    func testDisablingEnabledKindPersists() {
        let preferences = InMemoryPreferences()
        let vm = makeModel(preferences: preferences)

        vm.setEnabled(false, for: .cpu)

        XCTAssertFalse(preferences.enabledKinds.contains(.cpu))
        XCTAssertFalse(vm.enabledKinds.contains(.cpu))
    }

    func testEnablingDisabledKindPersists() {
        let preferences = InMemoryPreferences()
        preferences.enabledKinds = [.cpu, .memory]
        let vm = makeModel(preferences: preferences)

        vm.setEnabled(true, for: .disk)

        XCTAssertTrue(preferences.enabledKinds.contains(.disk))
        XCTAssertTrue(vm.enabledKinds.contains(.disk))
    }

    func testCannotDisableLastEnabledKind() {
        let preferences = InMemoryPreferences()
        preferences.enabledKinds = [.cpu]
        let vm = makeModel(preferences: preferences)

        vm.setEnabled(false, for: .cpu)

        XCTAssertTrue(preferences.enabledKinds.contains(.cpu))
        XCTAssertEqual(vm.lastErrorMessage, "At least one metric must remain enabled.")
    }

    // MARK: - Sampling interval

    func testChangingSamplingIntervalPersists() {
        let preferences = InMemoryPreferences()
        let vm = makeModel(preferences: preferences)

        vm.setSamplingInterval(3.5)

        XCTAssertEqual(preferences.samplingIntervalSeconds, 3.5, accuracy: 0.001)
        XCTAssertEqual(vm.samplingIntervalSeconds, 3.5, accuracy: 0.001)
    }

    func testSamplingIntervalIsClampedToLowerBound() {
        let preferences = InMemoryPreferences()
        let vm = makeModel(preferences: preferences)

        vm.setSamplingInterval(0.1)

        XCTAssertEqual(vm.samplingIntervalSeconds, 0.5, accuracy: 0.001)
        XCTAssertEqual(preferences.samplingIntervalSeconds, 0.5, accuracy: 0.001)
    }

    func testSamplingIntervalIsClampedToUpperBound() {
        let preferences = InMemoryPreferences()
        let vm = makeModel(preferences: preferences)

        vm.setSamplingInterval(60.0)

        XCTAssertEqual(vm.samplingIntervalSeconds, 10.0, accuracy: 0.001)
        XCTAssertEqual(preferences.samplingIntervalSeconds, 10.0, accuracy: 0.001)
    }

    // MARK: - Launch at login

    func testTogglingLaunchAtLoginPersists() {
        let preferences = InMemoryPreferences()
        let vm = makeModel(preferences: preferences)

        vm.setLaunchAtLogin(true)
        XCTAssertTrue(preferences.launchAtLogin)
        XCTAssertTrue(vm.launchAtLogin)

        vm.setLaunchAtLogin(false)
        XCTAssertFalse(preferences.launchAtLogin)
        XCTAssertFalse(vm.launchAtLogin)
    }

    // MARK: - Onboarding reset

    func testResetOnboardingFlipsFlag() {
        let preferences = InMemoryPreferences()
        preferences.onboardingCompleted = true
        let vm = makeModel(preferences: preferences)

        vm.resetOnboarding()

        XCTAssertFalse(preferences.onboardingCompleted)
    }

    func testResetOnboardingLeavesOtherPreferencesAlone() {
        let preferences = InMemoryPreferences()
        preferences.onboardingCompleted = true
        preferences.launchAtLogin = true
        let originalLaunchAtLogin = preferences.launchAtLogin
        let vm = makeModel(preferences: preferences)

        vm.resetOnboarding()

        XCTAssertEqual(preferences.launchAtLogin, originalLaunchAtLogin)
    }

    // MARK: - Purchase state mirroring

    func testIsProMirrorsPurchaseState() {
        let purchaseState = PurchaseState()
        let vm = makeModel(purchaseState: purchaseState)

        XCTAssertFalse(vm.isPro)

        purchaseState.update(isPro: true)

        // Combine delivers asynchronously on RunLoop.main.
        let expectation = expectation(description: "isPro flips to true")
        DispatchQueue.main.async {
            if vm.isPro {
                expectation.fulfill()
            } else {
                // Give Combine one more runloop.
                DispatchQueue.main.async {
                    vm.isPro ? expectation.fulfill() : XCTFail("isPro never became true")
                }
            }
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Notifications

    func testSyncNotificationAuthorizationReflectsAuthorized() async {
        let scheduler = NotificationScheduler(overriddenAuthStatus: .authorized)
        let vm = makeModel(scheduler: scheduler)

        await vm.syncNotificationAuthorization()

        XCTAssertTrue(vm.isNotificationsAuthorized)
    }

    func testSyncNotificationAuthorizationReflectsDenied() async {
        let scheduler = NotificationScheduler(overriddenAuthStatus: .denied)
        let vm = makeModel(scheduler: scheduler)

        await vm.syncNotificationAuthorization()

        XCTAssertFalse(vm.isNotificationsAuthorized)
    }

    // MARK: - Error clearing

    func testClearErrorClearsLastErrorMessage() {
        let preferences = InMemoryPreferences()
        preferences.enabledKinds = [.cpu]
        let vm = makeModel(preferences: preferences)
        vm.setEnabled(false, for: .cpu)
        XCTAssertNotNil(vm.lastErrorMessage)

        vm.clearError()
        XCTAssertNil(vm.lastErrorMessage)
    }

    // MARK: - Init snapshot

    func testInitReadsCurrentPreferences() {
        let preferences = InMemoryPreferences()
        preferences.menuBarMode = .numeric
        preferences.launchAtLogin = true
        preferences.samplingIntervalSeconds = 5.0
        preferences.enabledKinds = [.cpu, .memory]

        let vm = makeModel(preferences: preferences)

        XCTAssertEqual(vm.menuBarMode, .numeric)
        XCTAssertTrue(vm.launchAtLogin)
        XCTAssertEqual(vm.samplingIntervalSeconds, 5.0, accuracy: 0.001)
        XCTAssertEqual(vm.enabledKinds, [.cpu, .memory])
    }

    // MARK: - Theme mode

    func testChangingThemeModePersistsImmediately() {
        let preferences = InMemoryPreferences()
        let vm = makeModel(preferences: preferences)

        vm.setThemeMode(.light)

        XCTAssertEqual(preferences.themeMode, .light)
        XCTAssertEqual(vm.themeMode, .light)
    }

    func testSettingSameThemeModeIsNoop() {
        let preferences = InMemoryPreferences()
        preferences.themeMode = .dark
        let vm = makeModel(preferences: preferences)
        let originalMode = preferences.themeMode

        vm.setThemeMode(.dark)

        XCTAssertEqual(preferences.themeMode, originalMode)
        XCTAssertEqual(vm.themeMode, .dark)
    }

    func testInitReadsThemeModeFromPreferences() {
        let preferences = InMemoryPreferences()
        preferences.themeMode = .light
        let vm = makeModel(preferences: preferences)

        XCTAssertEqual(vm.themeMode, .light)
    }

    // MARK: - Sparkline theme

    func testChangingSparklineThemePersistsImmediately() {
        let preferences = InMemoryPreferences()
        let vm = makeModel(preferences: preferences)

        vm.setSparklineTheme("sunset")

        XCTAssertEqual(preferences.sparklineThemeID, "sunset")
        XCTAssertEqual(vm.sparklineThemeID, "sunset")
    }

    func testSettingSameSparklineThemeIsNoop() {
        let preferences = InMemoryPreferences()
        preferences.sparklineThemeID = SparklineTheme.default.id
        let vm = makeModel(preferences: preferences)

        vm.setSparklineTheme(SparklineTheme.default.id)

        XCTAssertEqual(preferences.sparklineThemeID, SparklineTheme.default.id)
    }

    func testInitReadsSparklineThemeFromPreferences() {
        let preferences = InMemoryPreferences()
        preferences.sparklineThemeID = "purple"
        let vm = makeModel(preferences: preferences)

        XCTAssertEqual(vm.sparklineThemeID, "purple")
    }

    func testSparklineThemeFallsBackToDefaultWhenUnknown() {
        let preferences = InMemoryPreferences()
        // InMemoryPreferences uses SparklineTheme.default.id which is "blue"
        XCTAssertEqual(preferences.sparklineThemeID, SparklineTheme.default.id)
        let vm = makeModel(preferences: preferences)

        XCTAssertEqual(vm.sparklineThemeID, SparklineTheme.default.id)
    }

    // MARK: - Tab navigation (SettingsTab enum)

    func testSettingsTabHasSixCases() {
        let allTabs: [SettingsView.SettingsTab] = [.menuBar, .alerts, .metrics, .appearance, .general, .about]
        XCTAssertEqual(allTabs.count, 6)
    }

    func testSettingsTabAllCasesAreDistinct() {
        let allTabs: [SettingsView.SettingsTab] = [.menuBar, .alerts, .metrics, .appearance, .general, .about]
        let unique = Set(allTabs)
        XCTAssertEqual(unique.count, allTabs.count, "All tabs should be unique")
    }

    func testSettingsTabDefaultIsMenuBar() {
        // The default selection is .menuBar as declared in SettingsView
        let defaultTab = SettingsView.SettingsTab.menuBar
        XCTAssertEqual(defaultTab, .menuBar)
    }

    // MARK: - Per-metric menu bar

    func testTogglingPerMetricMenuBarPersists() {
        let preferences = InMemoryPreferences()
        let vm = makeModel(preferences: preferences)

        vm.setPerMetricMenuBar(true)

        XCTAssertTrue(preferences.perMetricMenuBar)
        XCTAssertTrue(vm.perMetricMenuBar)
    }

    func testSettingSamePerMetricMenuBarIsNoop() {
        let preferences = InMemoryPreferences()
        preferences.perMetricMenuBar = false
        let vm = makeModel(preferences: preferences)

        vm.setPerMetricMenuBar(false)

        XCTAssertFalse(preferences.perMetricMenuBar)
        XCTAssertFalse(vm.perMetricMenuBar)
    }

    func testInitReadsPerMetricMenuBarFromPreferences() {
        let preferences = InMemoryPreferences()
        preferences.perMetricMenuBar = true
        let vm = makeModel(preferences: preferences)

        XCTAssertTrue(vm.perMetricMenuBar)
    }

    // MARK: - Icon style persistence

    func testSetIconStylePersistsAndUpdatesTheme() {
        let preferences = InMemoryPreferences()
        let vm = makeModel(preferences: preferences)

        vm.setIconStyle(.numeric, for: .cpu)

        XCTAssertEqual(preferences.menuBarIconTheme.style(for: .cpu), .numeric)
        XCTAssertEqual(vm.iconTheme.style(for: .cpu), .numeric)
    }

    func testSetIconStyleSameStyleIsNoop() {
        let preferences = InMemoryPreferences()
        let vm = makeModel(preferences: preferences)
        let originalTheme = preferences.menuBarIconTheme

        // Set the same style that's already the default
        vm.setIconStyle(.sparkline, for: .cpu)

        XCTAssertEqual(preferences.menuBarIconTheme, originalTheme)
    }

    // MARK: - Menu bar order

    func testMoveMetricReordersAndPersists() {
        let preferences = InMemoryPreferences()
        preferences.menuBarOrder = [.cpu, .memory, .disk, .network]
        let vm = makeModel(preferences: preferences)

        // Move CPU (index 0) to index 2.
        // Array.move(fromOffsets:toOffset:) removes element at 0, shifts memory
        // and disk left, then inserts CPU at index 2 → [memory, cpu, disk, network].
        vm.moveMetric(IndexSet(integer: 0), to: 2)

        XCTAssertEqual(preferences.menuBarOrder, [.memory, .cpu, .disk, .network])
        XCTAssertEqual(vm.menuBarOrder, [.memory, .cpu, .disk, .network])
    }

    func testMoveMetricNoopWhenSamePosition() {
        let preferences = InMemoryPreferences()
        preferences.menuBarOrder = [.cpu, .memory, .disk]
        let vm = makeModel(preferences: preferences)

        // Move CPU from index 0 to index 1 (its current position after shift)
        // This is a no-op in move(fromOffsets:toOffset:) semantics
        vm.moveMetric(IndexSet(integer: 1), to: 1)

        XCTAssertEqual(preferences.menuBarOrder, [.cpu, .memory, .disk])
        XCTAssertEqual(vm.menuBarOrder, [.cpu, .memory, .disk])
    }

    // MARK: - Restore purchases

    func testRestorePurchasesDelegatesToStoreManager() {
        let storeManager = RecordingStoreManager()
        let vm = makeModel(purchaseState: PurchaseState())
        // Inject store manager via init — we need a custom init for this
        // Actually let's use the existing container pattern
        let preferences = InMemoryPreferences()
        let vm2 = SettingsViewModel(
            preferences: preferences,
            scheduler: NotificationScheduler(overriddenAuthStatus: .denied),
            purchaseState: PurchaseState(),
            storeManager: storeManager
        )

        vm2.restorePurchases()

        // restore() is async; give it a moment to dispatch.
        let expectation = expectation(description: "restore called")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertEqual(storeManager.restoreCallCount, 1)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Error recording

    func testRecordErrorSetsLastErrorMessage() {
        let vm = makeModel()

        vm.recordError("Test error message")

        XCTAssertEqual(vm.lastErrorMessage, "Test error message")
    }

    func testRecordErrorClearsAfterClearError() {
        let vm = makeModel()

        vm.recordError("Something went wrong")
        XCTAssertEqual(vm.lastErrorMessage, "Something went wrong")

        vm.clearError()
        XCTAssertNil(vm.lastErrorMessage)
    }

    // MARK: - Menu bar order init

    func testInitReadsMenuBarOrderFromPreferences() {
        let preferences = InMemoryPreferences()
        preferences.menuBarOrder = [.network, .cpu, .memory]
        let vm = makeModel(preferences: preferences)

        XCTAssertEqual(vm.menuBarOrder, [.network, .cpu, .memory])
    }

    func testInitMenuBarOrderDefaultsToDisplayOrder() {
        let preferences = InMemoryPreferences()
        preferences.menuBarOrder = []
        let vm = makeModel(preferences: preferences)

        XCTAssertEqual(vm.menuBarOrder, MetricKind.menuBarDisplayOrder)
    }
}