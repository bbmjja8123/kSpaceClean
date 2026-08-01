import XCTest
import StoreKit
import Combine
import UserNotifications
import MetricsKit
@testable import kWatch

/// Verifies that `SettingsViewModel.restorePurchases()` propagates the
/// call to the injected `StoreManagerProtocol.restore()`.
///
/// The wiring itself already exists in production code (the About tab's
/// "Restore Purchases" button calls `viewModel.restorePurchases()` and
/// the view model dispatches a `Task` that invokes
/// `storeManager.restore()`). This test guards that contract so a
/// future refactor cannot silently drop the delegation.
@MainActor
final class SettingsViewModelRestoreTests: XCTestCase {

    func testRestorePurchasesPropagatesToStoreManager() async {
        // The view model dispatches the restore work on a detached
        // `Task` (matching the real button's fire-and-forget UX), so the
        // call returns synchronously. We pump the run loop until the
        // dispatched task has finished, then assert the stub recorded
        // exactly one `restore()` invocation.
        let stub = RecordingStoreManager()
        let preferences = StubPreferencesRepository()
        let scheduler = StubNotificationScheduler()
        let purchaseState = PurchaseState()
        let viewModel = SettingsViewModel(
            preferences: preferences,
            scheduler: scheduler,
            purchaseState: purchaseState,
            storeManager: stub
        )

        viewModel.restorePurchases()

        // Wait for the dispatched `Task` to complete. A short spin on
        // the main run loop is sufficient because `restore()` is a
        // trivial async function on the stub.
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        XCTAssertEqual(stub.restoreCallCount, 1)
    }

    func testRestorePurchasesInvokesStoreManagerExactlyOnce() async {
        // Calling restore multiple times should result in a matching
        // number of `restore()` invocations on the manager — guards
        // against accidental double-dispatch.
        let stub = RecordingStoreManager()
        let preferences = StubPreferencesRepository()
        let scheduler = StubNotificationScheduler()
        let purchaseState = PurchaseState()
        let viewModel = SettingsViewModel(
            preferences: preferences,
            scheduler: scheduler,
            purchaseState: purchaseState,
            storeManager: stub
        )

        viewModel.restorePurchases()
        viewModel.restorePurchases()
        viewModel.restorePurchases()

        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        XCTAssertEqual(stub.restoreCallCount, 3)
    }
}
