import Foundation
import AppIntents

/// Free intent. Brings kWatch to the foreground and navigates to the dashboard.
///
/// The AppIntents runtime cannot directly open a SwiftUI window, so this
/// intent posts a distributed notification that the main app observes in
/// `AppCoordinator`. When the app is not running the system launches it.
@available(macOS 13.0, *)
public struct OpenDashboardIntent: AppIntent {
    public static var title: LocalizedStringResource = "Open kWatch Dashboard"
    public static var description = IntentDescription(
        "Brings the kWatch window to the front.",
        categoryName: "kWatch"
    )

    /// `OpensIntent` causes the app to launch (if not running) and become
    /// frontmost when the shortcut is invoked.
    public static var openAppWhenRun: Bool = true

    public var serviceFactory: @Sendable () -> any IntentServiceProtocol

    public init() {
        self.serviceFactory = { LiveIntentService() }
    }

    public init(service: any IntentServiceProtocol) {
        self.serviceFactory = { service }
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = serviceFactory()
        await service.openDashboard()
        return .result(dialog: IntentDialog("Opening kWatch dashboard."))
    }
}