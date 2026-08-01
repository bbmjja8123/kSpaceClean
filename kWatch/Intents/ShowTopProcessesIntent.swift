import Foundation
import AppIntents

/// Lists the highest-CPU processes.
@available(macOS 13.0, *)
public struct ShowTopProcessesIntent: AppIntent {
    public static var title: LocalizedStringResource = "Show Top Processes"
    public static var description = IntentDescription(
        "Lists the highest-CPU processes.",
        categoryName: "kWatch"
    )

    @Parameter(title: "Limit", default: 10, inclusiveRange: (1, 50))
    public var limit: Int

    public var serviceFactory: @Sendable () -> any IntentServiceProtocol

    public init() {
        self.serviceFactory = { LiveIntentService() }
        self.limit = 10
    }

    public init(limit: Int = 10, service: any IntentServiceProtocol) {
        self.serviceFactory = { service }
        self.limit = limit
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = serviceFactory()
        await service.showTopProcesses(limit: limit)
        return .result(dialog: IntentDialog("Showing top \(limit) processes."))
    }
}
