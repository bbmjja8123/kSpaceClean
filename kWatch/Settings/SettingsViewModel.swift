import Foundation
import Combine
import DesignSystem
import AppKit
import MetricsKit
import StoreKit
import UserNotifications

/// Drives the Settings window.
///
/// Owns editable preferences (menu bar mode, enabled metric kinds, sampling
/// interval, launch-at-login) and proxies to `PreferencesRepositoryProtocol`
/// so every mutation is persisted immediately. The view model also exposes
/// derived state needed by the Settings UI (notification authorization
/// status, app version, Pro entitlement) and triggers side-effects such as
/// opening System Settings and exporting a diagnostics archive.
///
/// The view model is `@MainActor` because it publishes `@Published` state
/// that SwiftUI binds to from view bodies; all public methods must
/// therefore be invoked on the main actor.
@MainActor
public final class SettingsViewModel: ObservableObject {
    // MARK: - Published state

    /// Current menu bar presentation mode. Bound directly to the segmented
    /// picker in `MenuBarSettingsView`.
    @Published public var menuBarMode: MenuBarMode

    /// Which metric kinds the menu bar / dashboard surfaces. Iterated by the
    /// toggles in `MenuBarSettingsView` and filtered by `MetricsAggregator`.
    @Published public var enabledKinds: Set<MetricKind>

    /// Sampling interval in seconds. Persisted and consumed by the
    /// `SamplingStrategy` on the next aggregator restart.
    @Published public var samplingIntervalSeconds: Double

    /// Whether kWatch should be launched automatically at user login. Bound
    /// to a toggle in `WidgetSettingsView`.
    @Published public var launchAtLogin: Bool

    /// Per-metric menu-bar icon style theme. Each metric can independently
    /// render as sparkline, numeric, or minimal; mutations are persisted
    /// immediately through the preferences repository.
    @Published public var iconTheme: MenuBarIconTheme

    /// Whether each metric renders as its own menu-bar status item.
    @Published public var perMetricMenuBar: Bool

    /// Order in which per-metric status items appear (left to right).
    /// Falls back to `MetricKind.menuBarDisplayOrder` when unset.
    @Published public var menuBarOrder: [MetricKind]

    /// Whether the user has granted notification permission. Refreshed via
    /// `syncNotificationAuthorization()` whenever the view appears.
    @Published public private(set) var isNotificationsAuthorized: Bool = false

    /// Bundle version string (e.g. "1.0.0"). Cached at init so the About
    /// view does not have to touch `Bundle.main` repeatedly.
    @Published public private(set) var appVersion: String

    /// Build / short version string combined with the marketing version,
    /// formatted for the About view footer.
    @Published public private(set) var buildNumber: String

    /// Pro entitlement — used by the About view to render an Upgrade
    /// prompt when the user is on the Free tier.
    @Published public private(set) var isPro: Bool

    /// Last error surfaced through `PurchaseState.recordError(_:)`. Cleared
    /// by the view after it has shown an alert.
    @Published public private(set) var lastErrorMessage: String?

    // MARK: - Dependencies

    private var preferences: any PreferencesRepositoryProtocol
    private let scheduler: NotificationSchedulerProtocol
    private let purchaseState: PurchaseState
    private let storeManager: any StoreManagerProtocol
    private let diagnosticsExporter: DiagnosticsExporting

    // MARK: - Init

    public init(
        preferences: any PreferencesRepositoryProtocol,
        scheduler: NotificationSchedulerProtocol,
        purchaseState: PurchaseState,
        storeManager: any StoreManagerProtocol = NoopStoreManager(),
        diagnosticsExporter: DiagnosticsExporting = NoopDiagnosticsExporter()
    ) {
        self.preferences = preferences
        self.scheduler = scheduler
        self.purchaseState = purchaseState
        self.storeManager = storeManager
        self.diagnosticsExporter = diagnosticsExporter

        // Snapshot current preference values so the UI matches the
        // repository on first render.
        self.menuBarMode = preferences.menuBarMode
        self.enabledKinds = preferences.enabledKinds
        self.samplingIntervalSeconds = max(0.5, preferences.samplingIntervalSeconds)
        self.launchAtLogin = preferences.launchAtLogin
        self.iconTheme = preferences.menuBarIconTheme
        self.perMetricMenuBar = preferences.perMetricMenuBar
        self.menuBarOrder = preferences.menuBarOrder.isEmpty
            ? MetricKind.menuBarDisplayOrder
            : preferences.menuBarOrder
        self.isPro = purchaseState.isPro

        // Cache version strings from the main bundle. Fall back to "0.0.0"
        // if the keys are missing so the UI never crashes on unsigned dev
        // builds.
        let bundle = Bundle.main
        let marketing = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        self.appVersion = marketing
        self.buildNumber = "\(marketing) (\(build))"

        observePurchaseState()
    }

    // MARK: - Persisted mutations

    /// Update the menu bar presentation mode. Persisted on every change so
    /// the menu bar reflects the new style the next time it re-renders.
    public func setMenuBarMode(_ mode: MenuBarMode) {
        guard menuBarMode != mode else { return }
        menuBarMode = mode
        preferences.menuBarMode = mode
    }

    /// Set the menu-bar icon style for a single metric. Persisted on every
    /// change so the menu bar reflects the new style the next time it
    /// re-renders that metric's status icon.
    public func setIconStyle(_ style: MenuBarIcons.Style, for kind: MetricKind) {
        guard iconTheme.style(for: kind) != style else { return }
        iconTheme.set(style, for: kind)
        preferences.menuBarIconTheme = iconTheme
    }

    /// Toggle a single metric kind on or off. Persisted immediately.
    public func setEnabled(_ enabled: Bool, for kind: MetricKind) {
        var copy = enabledKinds
        if enabled {
            copy.insert(kind)
        } else {
            // Guarantee at least one kind stays enabled so the menu bar
            // never renders an empty row.
            if copy.count > 1 {
                copy.remove(kind)
            } else {
                recordError("At least one metric must remain enabled.")
                return
            }
        }
        enabledKinds = copy
        preferences.enabledKinds = copy
    }

    /// Update the sampling interval. Values are clamped to a sensible
    /// range so the UI slider cannot freeze the aggregator at 0s or push
    /// it to a one-second-per-sample crawl.
    public func setSamplingInterval(_ seconds: Double) {
        let clamped = min(max(seconds, 0.5), 10.0)
        guard samplingIntervalSeconds != clamped else { return }
        samplingIntervalSeconds = clamped
        preferences.samplingIntervalSeconds = clamped
    }

    /// Toggle launch-at-login. Persisted immediately. Actual login-item
    /// registration is owned by `LaunchAtLoginManager`; the preference is
    /// the source of truth used by the menu bar / About diagnostics.
    public func setLaunchAtLogin(_ enabled: Bool) {
        guard launchAtLogin != enabled else { return }
        launchAtLogin = enabled
        preferences.launchAtLogin = enabled
    }

    /// Toggle multi-icon mode: one menu-bar status item per metric.
    /// Persisted immediately so the next launch restores the same layout.
    public func setPerMetricMenuBar(_ enabled: Bool) {
        guard enabled != perMetricMenuBar else { return }
        perMetricMenuBar = enabled
        preferences.perMetricMenuBar = enabled
    }

    /// Move a metric to a new position in the menu-bar order. Persisted
    /// immediately; the menu bar reflects the new order on the next update.
    public func moveMetric(_ source: IndexSet, to destination: Int) {
        var order = menuBarOrder
        order.move(fromOffsets: source, toOffset: destination)
        guard order != menuBarOrder else { return }
        menuBarOrder = order
        preferences.menuBarOrder = order
    }

    // MARK: - Onboarding reset

    /// Clear the onboarding completion flag so the next launch shows the
    /// four-step flow again. Settings stay intact — only the gating flag
    /// is flipped.
    public func resetOnboarding() {
        preferences.onboardingCompleted = false
    }

    // MARK: - Notifications

    /// Read the current notification authorization status without prompting
    /// the user. Called from `SettingsView.onAppear`.
    public func syncNotificationAuthorization() async {
        let status = await scheduler.authorizationStatus
        isNotificationsAuthorized = (status == .authorized || status == .provisional)
    }

    /// Request notification permission from the user and refresh the
    /// authorization flag once the system responds.
    public func requestNotificationPermission() async {
        await scheduler.requestAuthorization()
        await syncNotificationAuthorization()
    }

    /// Open the Notifications pane in System Settings so the user can
    /// change the permission even if the in-app prompt was denied.
    public func openNotificationSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Diagnostics export

    /// Export a diagnostics bundle to the user's Desktop and return the
    /// resulting URL. Returns `nil` when no exporter is wired (test path).
    public func exportDiagnostics() async -> URL? {
        do {
            return try await diagnosticsExporter.export()
        } catch {
            recordError("Diagnostics export failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Support & policy links

    /// Open the privacy policy page in the default browser.
    public func openPrivacyPolicy() {
        openURL(Self.privacyPolicyURL)
    }

    /// Open the support page in the default browser.
    public func openSupport() {
        openURL(Self.supportURL)
    }

    /// Open the open-source licenses acknowledgements page.
    public func openLicenses() {
        openURL(Self.licensesURL)
    }

    private func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Public so views can render the URLs as text labels when needed.
    public static let privacyPolicyURL: URL = URL(string: "https://kraftly.app/kwatch/privacy")!
    public static let supportURL: URL = URL(string: "https://kraftly.app/kwatch/support")!
    public static let licensesURL: URL = URL(string: "https://kraftly.app/kwatch/licenses")!

    // MARK: - PurchaseState observation

    private var purchaseCancellable: AnyCancellable?

    private func observePurchaseState() {
        // Mirror the latest Pro flag so the About view can swap between
        // "Upgrade" and "Thank you" copy without a manual refresh.
        purchaseCancellable = purchaseState.$isPro
            .receive(on: RunLoop.main)
            .sink { [weak self] newValue in
                self?.isPro = newValue
            }
    }

    // MARK: - Errors

    /// Forward an error message to both `PurchaseState.recordError` (so it
    /// shows up in the menu bar banner) and the local `lastErrorMessage`
    /// so the Settings view can render a confirmation alert.
    public func recordError(_ message: String) {
        purchaseState.recordError(message)
        lastErrorMessage = message
    }

    /// Clear the locally tracked error after the view has presented it.
    public func clearError() {
        lastErrorMessage = nil
    }

    // MARK: - StoreKit

    /// Ask the StoreKit manager to re-check the user's existing
    /// entitlements and update the Pro flag accordingly. Wired into the
    /// "Restore Purchases" action on the About tab.
    public func restorePurchases() {
        Task { await storeManager.restore() }
    }
}

/// Lightweight placeholder `StoreManagerProtocol` used when Settings is
/// instantiated without a container (e.g. SwiftUI previews or older test
/// paths). All methods are no-ops so the views still render without
/// touching StoreKit.
public final class NoopStoreManager: StoreManagerProtocol, @unchecked Sendable {
    public let productID: String = "app.kraftly.kwatch.pro"

    public init() {}

    public var products: [Product] { [] }

    public var isPro: Bool { false }

    public var primaryProduct: Product? { nil }

    public func refreshEntitlements() async {}

    public func loadProducts() async {}

    public func purchase() async {}

    public func restore() async {}

    public func finish(_ transaction: Transaction) async {
        _ = transaction
    }
}

// MARK: - Diagnostics exporting

/// Boundary so production code can inject a real archive builder while
/// tests and the no-op container pass through `NoopDiagnosticsExporter`.
public protocol DiagnosticsExporting: Sendable {
    func export() async throws -> URL
}

/// Default exporter used when no real implementation is wired. Returns
/// `nil` from the view model rather than throwing so the UI can simply
/// fall through.
public struct NoopDiagnosticsExporter: DiagnosticsExporting {
    public init() {}

    public func export() async throws -> URL {
        throw DiagnosticsExporterError.notConfigured
    }
}

/// Errors raised by `DiagnosticsExporting` implementations.
public enum DiagnosticsExporterError: LocalizedError {
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Diagnostics export is not configured in this build."
        }
    }
}