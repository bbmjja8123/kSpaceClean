import XCTest
import MetricsKit
@testable import kWatch

// MARK: - SettingsViewModelTests

@MainActor
final class SettingsViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeModel(
        preferences: PreferencesRepositoryProtocol = InMemoryPreferences(),
        scheduler: NotificationSchedulerProtocol = NotificationScheduler(
            overriddenAuthStatus: .denied
        ),
        purchaseState: PurchaseState = PurchaseState()
    ) -> SettingsViewModel {
        SettingsViewModel(
            preferences: preferences,
            scheduler: scheduler,
            purchaseState: purchaseState
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
}