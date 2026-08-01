import Foundation
import AppIntents

/// Pro-gated intent. Asks kWatch to write a diagnostics archive and returns
/// the resulting path so Shortcuts can pass it on to the next action.
@available(macOS 13.0, *)
public struct ExportDiagnosticsIntent: AppIntent {
    public static var title: LocalizedStringResource = "Export Diagnostics"
    public static var description = IntentDescription(
        "Creates a local diagnostics archive. Requires kWatch Pro.",
        categoryName: "kWatch Pro"
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
        guard await service.isPro() else {
            let locked = lockedDialogText()
            return .result(value: "", dialog: IntentDialog("\(locked)"))
        }
        do {
            let url = try await service.exportDiagnostics()
            let line = "Diagnostics exported to \(url.path)"
            return .result(value: url.path, dialog: IntentDialog("\(line)"))
        } catch {
            return .result(value: "", dialog: IntentDialog("Diagnostics export failed: \(error.localizedDescription)"))
        }
    }
}