import AppKit

/// Bridges AppKit lifecycle events to the shared app coordinator.
public final class kWatchAppDelegate: NSObject, NSApplicationDelegate {
    public static let shared = kWatchAppDelegate()

    public let container: LiveAppContainer
    private var coordinator: AppCoordinator?

    private override init() {
        self.container = LiveAppContainer()
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator(container: container)
        self.coordinator = coordinator
        coordinator.start()

        // Subscribe to MetricKit so daily performance summaries and any
        // crash/hang payloads are written to the App Group container.
        // MetricKitSubscriber.start() is idempotent and runs only on the
        // main actor.
        container.metricKitSubscriber.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }
}
