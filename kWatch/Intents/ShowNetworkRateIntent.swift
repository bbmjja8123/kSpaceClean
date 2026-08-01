import Foundation
import AppIntents
import MetricsKit

/// Returns the current network throughput.
@available(macOS 13.0, *)
public struct ShowNetworkRateIntent: AppIntent {
    public static var title: LocalizedStringResource = "Show Network Rate"
    public static var description = IntentDescription(
        "Reports current network throughput.",
        categoryName: "kWatch"
    )

    @Parameter(title: "Direction", default: .combined)
    public var direction: NetworkDirectionParameter

    public var serviceFactory: @Sendable () -> any IntentServiceProtocol

    public init() {
        self.serviceFactory = { LiveIntentService() }
        self.direction = .combined
    }

    public init(direction: NetworkDirectionParameter = .combined, service: any IntentServiceProtocol) {
        self.serviceFactory = { service }
        self.direction = direction
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = serviceFactory()
        await service.showNetworkRate(direction: direction)
        return .result(dialog: IntentDialog("Showing \(direction.displayName.lowercased()) network rate."))
    }
}

@available(macOS 13.0, *)
public enum NetworkDirectionParameter: String, AppEnum, Sendable {
    case combined = "combined"
    case download = "download"
    case upload = "upload"

    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Direction"
    public static var caseDisplayRepresentations: [NetworkDirectionParameter: DisplayRepresentation] = [
        .combined: DisplayRepresentation(title: "Combined"),
        .download: DisplayRepresentation(title: "Download"),
        .upload: DisplayRepresentation(title: "Upload")
    ]

    /// Human-readable name used in dialogs.
    public var displayName: String {
        switch self {
        case .combined: return "Combined"
        case .download: return "Download"
        case .upload: return "Upload"
        }
    }
}
