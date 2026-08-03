import Foundation
import AppIntents

/// Pro-gated intent. Pauses kWatch's background sampling loop.
///
/// Distinct from `StopMonitoringIntent` (which is the Shortcuts surface) so
/// the widget can show a confirmation dialog without the destructive-stop
/// wording. Internally both call `service.stopMonitoring()` — pausing is
/// idempotent and the service is responsible for the actual side effect.
///
/// Free users see the standard locked-dialog copy.
@available(macOS 14.0, *)
public struct PauseMonitoringIntent: AppIntent {
    public static var title: LocalizedStringResource = "Pause kWatch Monitoring"
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