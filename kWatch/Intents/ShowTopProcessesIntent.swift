import Foundation
import AppIntents

/// Pro-gated intent. Returns the top CPU consumers as a dialog line.
@available(macOS 13.0, *)
public struct ShowTopProcessesIntent: AppIntent {
    public static var title: LocalizedStringResource = "Show Top Processes"
    public static var description = IntentDescription(
        "Lists the highest-CPU processes. Requires kWatch Pro.",
        categoryName: "kWatch Pro"
    )

    @Parameter(title: "Limit", default: 10, inclusiveRange: (1, 50))
    public var limit: Int

    public var serviceFactory: @Sendable () -> any IntentServiceProtocol

    public init() {
        self.limit = 10
        self.serviceFactory = { LiveIntentService() }
    }

    public init(limit: Int = 10, service: any IntentServiceProtocol) {
        self.limit = limit
        self.serviceFactory = { service }
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = serviceFactory()
        await service.showTopProcesses(limit: limit)
        return .result(dialog: IntentDialog("Showing top \(limit) processes."))
    }
}
