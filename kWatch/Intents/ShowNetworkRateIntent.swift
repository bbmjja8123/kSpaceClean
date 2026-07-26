import Foundation
import AppIntents
import MetricsKit

/// Pro-gated intent. Returns the current network throughput.
@available(macOS 13.0, *)
public struct ShowNetworkRateIntent: AppIntent {
    public static var title: LocalizedStringResource = "Show Network Rate"
    public static var description = IntentDescription(
        "Reports current network throughput. Requires kWatch Pro.",
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
            return .result(dialog: IntentDialog(lockedDialogText()))
        }
        let snapshot = await service.latestSnapshot()
        guard let snapshot else {
            return .result(dialog: IntentDialog(IntentFormatter.unavailable(for: .network)))
        }
        let formatted = IntentFormatter.format(kind: .network, snapshot: snapshot)
        let line = "Network throughput is \(formatted)."
        return .result(value: line, dialog: IntentDialog(line))
    }
}