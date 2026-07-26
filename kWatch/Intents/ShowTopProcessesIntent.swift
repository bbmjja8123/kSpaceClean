import Foundation
import AppIntents

/// Pro-gated intent. Returns the top five CPU consumers as a dialog line.
@available(macOS 13.0, *)
public struct ShowTopProcessesIntent: AppIntent {
    public static var title: LocalizedStringResource = "Show Top Processes"
    public static var description = IntentDescription(
        "Lists the five highest-CPU processes. Requires kWatch Pro.",
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
        let processes = (try? await service.topProcesses(limit: 5)) ?? []
        guard !processes.isEmpty else {
            return .result(dialog: IntentDialog("No process data available."))
        }
        let lines = processes.prefix(5).map { p -> String in
            "\(p.name) — \(Int(p.cpuPercent.rounded()))%"
        }
        return .result(
            dialog: IntentDialog("Top processes:\n" + lines.joined(separator: "\n"))
        )
    }
}