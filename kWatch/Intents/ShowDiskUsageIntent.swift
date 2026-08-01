import Foundation
import AppIntents
import MetricsKit

/// Free intent. Returns the current disk usage percentage and free space.
@available(macOS 13.0, *)
public struct ShowDiskUsageIntent: AppIntent {
    public static var title: LocalizedStringResource = "Show Disk Usage"
    public static var description = IntentDescription(
        "Returns the percentage of the chosen disk volume in use.",
        categoryName: "kWatch"
    )

    @Parameter(title: "Volume", default: .system)
    public var volume: DiskVolumeParameter

    public var serviceFactory: @Sendable () -> any IntentServiceProtocol

    public init() {
        self.volume = .system
        self.serviceFactory = { LiveIntentService() }
    }

    public init(volume: DiskVolumeParameter = .system, service: any IntentServiceProtocol) {
        self.volume = volume
        self.serviceFactory = { service }
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = serviceFactory()
        await service.showDiskUsage(volume: volume)
        return .result(dialog: IntentDialog("Showing disk usage for \(volume.displayName.lowercased()) volume."))
    }
}

@available(macOS 13.0, *)
public enum DiskVolumeParameter: String, AppEnum, Sendable {
    case system = "system"
    case data = "data"
    case external = "external"

    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Volume"
    public static var caseDisplayRepresentations: [DiskVolumeParameter: DisplayRepresentation] = [
        .system: DisplayRepresentation(title: "System volume"),
        .data: DisplayRepresentation(title: "Data volume"),
        .external: DisplayRepresentation(title: "External volumes")
    ]

    /// Human-readable name used in dialogs.
    public var displayName: String {
        switch self {
        case .system: return "System"
        case .data: return "Data"
        case .external: return "External"
        }
    }
}
