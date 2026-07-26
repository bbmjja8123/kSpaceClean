import Foundation
import AppIntents
import MetricsKit

/// Free intent. Returns the latest formatted value for any `MetricKind`.
///
/// Users invoke this from Shortcuts ("Ask kWatch for CPU") or Spotlight. The
/// returned value is short so it fits cleanly in a Spotlight result card.
@available(macOS 13.0, *)
public struct QueryMetricIntent: AppIntent {
    public static var title: LocalizedStringResource = "Ask kWatch for a metric"
    public static var description = IntentDescription(
        "Returns the latest CPU, memory, disk, network, temperature, fan, or battery value.",
        categoryName: "kWatch"
    )

    @Parameter(title: "Metric")
    public var metric: MetricKindParameter

    /// Internal hook used by tests to inject canned data. Defaults to
    /// `LiveIntentService` in production.
    public var serviceFactory: @Sendable () -> any IntentServiceProtocol

    public init() {
        self.metric = .cpu
        self.serviceFactory = { LiveIntentService() }
    }

    public init(metric: MetricKindParameter, service: any IntentServiceProtocol) {
        self.metric = metric
        self.serviceFactory = { service }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let service = serviceFactory()
        let formatted = await service.formatMetric(kind: metric.kind)
        return .result(
            value: formatted,
            dialog: IntentDialog("kWatch: \(metric.kind.displayName) is \(formatted).")
        )
    }
}

/// Strongly-typed `AppEnum` wrapper around `MetricKind` so we can use it as
/// an `@Parameter` on the AppIntents runtime.
@available(macOS 13.0, *)
public struct MetricKindParameter: AppEnum, Sendable {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Metric"
    public static var caseDisplayRepresentations: [MetricKindParameter: DisplayRepresentation] = [
        .cpu: DisplayRepresentation(title: "CPU"),
        .memory: DisplayRepresentation(title: "Memory"),
        .disk: DisplayRepresentation(title: "Disk"),
        .network: DisplayRepresentation(title: "Network"),
        .temperature: DisplayRepresentation(title: "Temperature"),
        .fan: DisplayRepresentation(title: "Fan"),
        .battery: DisplayRepresentation(title: "Battery")
    ]

    public let kind: MetricKind

    public init?(rawValue: String) {
        guard let k = MetricKind(rawValue: rawValue) else { return nil }
        self.kind = k
    }

    public var rawValue: String { kind.rawValue }

    public static let cpu = MetricKindParameter(kind: .cpu)
    public static let memory = MetricKindParameter(kind: .memory)
    public static let disk = MetricKindParameter(kind: .disk)
    public static let network = MetricKindParameter(kind: .network)
    public static let temperature = MetricKindParameter(kind: .temperature)
    public static let fan = MetricKindParameter(kind: .fan)
    public static let battery = MetricKindParameter(kind: .battery)

    public static var allCases: [MetricKindParameter] {
        MetricKind.allCases.map { MetricKindParameter(kind: $0) }
    }
}

@available(macOS 13.0, *)
public extension MetricKind {
    /// Human-readable name used in dialogs.
    var displayName: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .network: return "Network"
        case .temperature: return "Temperature"
        case .fan: return "Fan"
        case .battery: return "Battery"
        }
    }
}