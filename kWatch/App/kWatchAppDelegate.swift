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
    }

    public func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }
}
