import Foundation
import UserNotifications
import MetricsKit
@testable import kWatch

// MARK: - StubPreferencesRepository

/// Test-only `PreferencesRepositoryProtocol` implementation backed by simple
/// stored properties. Lets tests construct a `SettingsViewModel` without
/// touching `UserDefaults` or the App Group container.
final class StubPreferencesRepository: PreferencesRepositoryProtocol, @unchecked Sendable {
    var menuBarMode: MenuBarMode = .trend
    var enabledKinds: Set<MetricKind> = [.cpu, .memory, .disk, .network]
    var samplingIntervalSeconds: Double = 2.0
    var onboardingCompleted: Bool = false
    var launchAtLogin: Bool = false

    init() {}
}

// MARK: - StubNotificationScheduler

/// Test-only `NotificationSchedulerProtocol` that records authorization
/// status, returns it on demand, and swallows all schedule/remove calls so
/// `SettingsViewModel` can be exercised without touching
/// `UNUserNotificationCenter`.
final class StubNotificationScheduler: NotificationSchedulerProtocol, @unchecked Sendable {
    var authorizationStatusValue: UNAuthorizationStatus

    init(authorizationStatus: UNAuthorizationStatus = .denied) {
        self.authorizationStatusValue = authorizationStatus
    }

    var authorizationStatus: UNAuthorizationStatus {
        get async { authorizationStatusValue }
    }

    func requestAuthorization() async {
        // Mirror what a real grant looks like so the view model's
        // `isNotificationsAuthorized` flag updates if the test cares.
        authorizationStatusValue = .authorized
    }

    func schedule(alert: MetricAlert, value: MetricValue) async {
        // No-op for tests.
    }

    func removePending(alertID: UUID) async {
        // No-op for tests.
    }
}

// MARK: - RecordingStoreManager

/// Stub `StoreManagerProtocol` that records how many times `restore()` is
/// called. Mirrors the structure of the production `StubStoreManager` but
/// exposes a simple counter so the new wiring test can assert that
/// `SettingsViewModel.restorePurchases()` delegates to the manager.
@MainActor
final class RecordingStoreManager: StoreManagerProtocol, ObservableObject, @unchecked Sendable {
    let productID: String = "app.kraftly.kwatch.pro"
    @Published var products: [Product] = []
    @Published var isPro: Bool = false
    var primaryProduct: Product? { nil }
    var restoreCallCount: Int = 0

    init() {}

    func refreshEntitlements() async {}
    func loadProducts() async {}
    func purchase() async {}
    func restore() async { restoreCallCount += 1 }
    func finish(_ transaction: Transaction) async {
        _ = transaction
    }
}
