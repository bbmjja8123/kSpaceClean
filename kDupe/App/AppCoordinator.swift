import SwiftUI
import Foundation

public final class AppCoordinator: ObservableObject, @unchecked Sendable {
    public weak var appState: AppState?

    /// The single AppCoordinator the C-level Darwin-notify callback can
    /// reach. kSiftApp sets this in `onAppear`; the static lets the C
    /// function pointer route back to a Swift instance without capture.
    /// `@unchecked Sendable` on the class above makes this mutable static
    /// legal under strict concurrency — the race window is bounded to
    /// startup (one write) and the C callback (one read).
    public static var active: AppCoordinator?

    private static let finderSyncNotificationName: CFNotificationName =
        CFNotificationName("com.kraftly.ksift.scanFolder" as CFString)
    private static let finderSyncPendingPathKey = "ksift.finderSync.pendingPath"
    private static let appGroupSuite = "group.app.kraftly.ksift"

    public init(appState: AppState? = nil) {
        self.appState = appState
    }

    @discardableResult
    @MainActor
    public func handleDeepLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme, scheme == "ksift",
              let host = url.host else { return false }
        switch host {
        case "scan":
            appState?.navigation = .scan
            return true
        case "results":
            appState?.navigation = .results
            return true
        default:
            return false
        }
    }

    @MainActor
    public func navigate(to item: AppState.NavigationItem) {
        appState?.navigation = item
    }

    // MARK: - Finder Sync handoff

    /// Registers a Darwin-notify observer that the Finder Sync extension
    /// pings when the user picks "Scan with kSift". The actual folder path
    /// is read from the shared App Group UserDefaults (the extension writes
    /// it before posting).
    public func startObservingFinderScanRequests() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        Self.active = self
        CFNotificationCenterAddObserver(
            center,
            nil,
            { _, _, _, _, _ in
                AppCoordinator.handleFinderScanRequestCallback()
            },
            Self.finderSyncNotificationName.rawValue,
            nil,
            .deliverImmediately
        )
    }

    /// If the extension fired while the app wasn't running, its write to
    /// shared UserDefaults is still there at next launch. Drain it.
    @MainActor
    public func drainPendingFinderScanRequest() {
        guard let path = Self.readPendingFinderPath() else { return }
        Self.clearPendingFinderPath()
        handleFinderScanRequest(path: path)
    }

    /// Called on the main actor (either from the Darwin callback's
    /// main-hop or from `drainPendingFinderScanRequest`). Publishing
    /// `pendingScanPath` and switching to `.scan` lets MainView's
    /// `.onAppear` trigger a scan with `customDirectories: [path]`.
    @MainActor
    public func handleFinderScanRequest(path: String) {
        guard !path.isEmpty else { return }
        appState?.pendingScanPath = path
        appState?.navigation = .scan
    }

    // MARK: - Private

    /// Bridge from the C callback into Swift. Reads the path, then hops to
    /// the main actor and forwards to the active coordinator.
    private static func handleFinderScanRequestCallback() {
        guard let path = readPendingFinderPath() else { return }
        clearPendingFinderPath()
        Task { @MainActor in
            active?.handleFinderScanRequest(path: path)
        }
    }

    private static func readPendingFinderPath() -> String? {
        let defaults = UserDefaults(suiteName: appGroupSuite) ?? .standard
        let path = defaults.string(forKey: finderSyncPendingPathKey)
        return (path?.isEmpty == false) ? path : nil
    }

    private static func clearPendingFinderPath() {
        let defaults = UserDefaults(suiteName: appGroupSuite) ?? .standard
        defaults.removeObject(forKey: finderSyncPendingPathKey)
    }
}