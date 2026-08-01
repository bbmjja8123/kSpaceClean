import Foundation
import AppIntents

/// Pro-gated intent. Pauses kWatch's background sampling loop.
///
/// Free users see a locked-dialog copy pointing them at the Pro upgrade; the
/// side-effect (`stopMonitoring`) is intentionally not called for them.
@available(macOS 13.0, *)
public struct StopMonitoringIntent: AppIntent {
    public static var title: LocalizedStringResource = "Stop kWatch Monitoring"
    public static var description = IntentDescription(
        "Pauses background sampling. Requires kWatch Pro.",
        categoryName: "kWatch Pro"
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
        return .result(dialog: IntentDialog("kWatch monitoring paused."))
    }
}

/// Returns the standard locked-dialog copy. Centralized so the same wording
/// appears for every Pro-gated intent.
@available(macOS 13.0, *)
public func lockedDialogText() -> String {
    "This action requires kWatch Pro. Open the app and upgrade from Settings."
}