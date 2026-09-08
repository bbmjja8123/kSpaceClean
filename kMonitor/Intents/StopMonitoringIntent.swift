import Foundation
import AppIntents

/// Pro-gated intent. Pauses kMonitor's background sampling loop.
///
/// Free users see a locked-dialog copy pointing them at the Pro upgrade; the
/// side-effect (`stopMonitoring`) is intentionally not called for them.
@available(macOS 13.0, *)
public struct StopMonitoringIntent: AppIntent {
    public static var title: LocalizedStringResource = "Stop kMonitor Monitoring"
    public static var description = IntentDescription(
        "Pauses background sampling. Requires kMonitor Pro.",
        categoryName: "kMonitor Pro"
    )

    public var serviceFactory: @Sendable () -> any IntentServiceProtocol

    public init() {
        self.serviceFactory = { LiveIntentService() }
    }

    public init(service: any IntentServiceProtocol) {
        self.serviceFactory = { service }
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = serviceFactory()
        guard await service.isPro() else {
            return .result(dialog: IntentDialog("\(lockedDialogText())"))
        }
        await service.stopMonitoring()
        return .result(dialog: IntentDialog("kMonitor monitoring paused."))
    }
}

/// Returns the standard locked-dialog copy. Centralized so the same wording
/// appears for every Pro-gated intent.
@available(macOS 13.0, *)
public func lockedDialogText() -> String {
    String(localized: "This action requires kMonitor Pro. Open the app and upgrade from Settings.")
}