import Foundation
import AppIntents
import MetricsKit

/// Free intent. Returns the current disk usage percentage and free space.
@available(macOS 13.0, *)
public struct ShowDiskUsageIntent: AppIntent {
    public static var title: LocalizedStringResource = "Show Disk Usage"
    public static var description = IntentDescription(
        "Returns the percentage of the boot disk in use.",
        categoryName: "kWatch"
    )

    public var serviceFactory: @Sendable () -> any IntentServiceProtocol

    public init() {
        self.serviceFactory = { LiveIntentService() }
    }

    public init(service: any IntentServiceProtocol) {
        self.serviceFactory = { service }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let service = serviceFactory()
        let snapshot = await service.latestSnapshot()
        guard let snapshot, let value = snapshot.values[.disk] else {
            return .result(
                value: IntentFormatter.unavailable(for: .disk),
                dialog: IntentDialog(IntentFormatter.unavailable(for: .disk))
            )
        }
        switch value {
        case .percentage(let p):
            let line = "Disk usage is \(Int(p.rounded()))%."
            return .result(value: line, dialog: IntentDialog(line))
        default:
            let na = IntentFormatter.unavailable(for: .disk)
            return .result(value: na, dialog: IntentDialog(na))
        }
    }
}