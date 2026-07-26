import Foundation
import AppIntents

/// Free intent. Tells kWatch to start continuous metric sampling.
@available(macOS 13.0, *)
public struct StartMonitoringIntent: AppIntent {
    public static var title: LocalizedStringResource = "Start kWatch Monitoring"
    public static var description = IntentDescription(
        "Begins background sampling of CPU, memory, disk, and network metrics.",
        categoryName: "kWatch"
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
        await service.startMonitoring()
        return .result(dialog: IntentDialog("kWatch monitoring started."))
    }
}