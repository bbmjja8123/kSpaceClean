import Foundation
import Combine
import MetricsKit

/// Allow `MetricKind` to be used with SwiftUI's `.sheet(item:)`.
extension MetricKind: Identifiable {
    public var id: String { rawValue }
}

/// View model for the metric detail sheet, showing a trend chart, summary
/// statistics, and top processes for a single metric kind.
///
/// The model loads history from the repository, downsamples it for chart
/// rendering, computes min/max/avg, and optionally fetches the top processes
/// from the system process monitor. Free users see a Pro gate — the
/// repository is never queried until Pro entitlement is active.
@MainActor
public final class MetricDetailViewModel: ObservableObject {
    // MARK: - Range

    /// Compact time-range selector for the detail sheet.
    public enum Range: String, CaseIterable, Identifiable {
        case h24, d7, d30
        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .h24: return String(localized: "24H")
            case .d7:   return String(localized: "7D")
            case .d30:  return String(localized: "30D")
            }
        }

        /// The duration for this range.
        public var duration: TimeInterval {
            switch self {
            case .h24: return 24 * 60 * 60
            case .d7:  return 7 * 24 * 60 * 60
            case .d30: return 30 * 24 * 60 * 60
            }
        }
    }

    // MARK: - Published state

    /// The metric kind being displayed.
    @Published public private(set) var kind: MetricKind

    /// Currently selected time range.
    @Published public var selectedRange: Range = .h24

    /// Downsampled chart points ready for rendering.
    @Published public private(set) var points: [ChartPoint] = []

    /// Minimum value across the loaded series.
    @Published public private(set) var minValue: Double = 0

    /// Maximum value across the loaded series.
    @Published public private(set) var maxValue: Double = 0

    /// Average value across the loaded series.
    @Published public private(set) var avgValue: Double = 0

    /// Formatted display strings for the summary row.
    @Published public private(set) var minDisplay: String = "--"
    @Published public private(set) var avgDisplay: String = "--"
    @Published public private(set) var maxDisplay: String = "--"

    /// Top processes sorted by the relevant metric.
    @Published public private(set) var processRows: [ProcessRow] = []

    /// Loading indicator.
    @Published public private(set) var isLoading = false

    /// Whether the current metric kind supports process listing.
    public var supportsProcesses: Bool {
        switch kind {
        case .cpu, .memory, .network: return true
        default: return false
        }
    }

    /// Whether the user has Pro entitlement.
    public var isPro: Bool { purchaseState.isPro }

    /// The accent color for the chart line, derived from the metric kind.
    public var chartColor: CardColor {
        switch kind {
        case .cpu:         return .blue
        case .memory:      return .green
        case .disk:        return .orange
        case .network:     return .purple
        case .temperature: return .red
        case .fan:         return .yellow
        case .battery:     return .green
        case .gpu:         return .purple
        }
    }

    /// Human-readable display title for the metric kind.
    public var kindTitle: String {
        switch kind {
        case .cpu:         return String(localized: "CPU")
        case .memory:      return String(localized: "Memory")
        case .disk:        return String(localized: "Disk")
        case .network:     return String(localized: "Network")
        case .temperature: return String(localized: "Temperature")
        case .fan:         return String(localized: "Fan")
        case .battery:     return String(localized: "Battery")
        case .gpu:         return String(localized: "GPU")
        }
    }

    // MARK: - Dependencies

    private let historyRepo: any HistoryRepositoryProtocol
    private let purchaseState: PurchaseState
    private let processMonitor: ProcessMonitor?

    // MARK: - Init

    public init(
        kind: MetricKind,
        historyRepo: any HistoryRepositoryProtocol,
        purchaseState: PurchaseState,
        processMonitor: ProcessMonitor? = nil
    ) {
        self.kind = kind
        self.historyRepo = historyRepo
        self.purchaseState = purchaseState
        self.processMonitor = processMonitor
    }

    // MARK: - Public API

    /// Load history data for the current `kind` and `selectedRange`.
    public func load() async {
        guard purchaseState.isPro else {
            points = []
            clearStats()
            processRows = []
            return
        }

        isLoading = true

        let now = Date()
        let since = now.addingTimeInterval(-selectedRange.duration)

        do {
            let snapshots = try historyRepo.samples(since: since)

            let fullSeries = snapshots.compactMap { snapshot -> ChartPoint? in
                guard let value = extractDouble(
                    from: snapshot.values[self.kind],
                    for: self.kind
                ) else {
                    return nil
                }
                return ChartPoint(date: snapshot.timestamp, value: value)
            }
            .sorted { $0.date < $1.date }

            computeStats(from: fullSeries)
            points = downsample(points: fullSeries, maxCount: 500)

            if supportsProcesses {
                loadProcesses()
            } else {
                processRows = []
            }
        } catch {
            points = []
            clearStats()
            processRows = []
        }

        isLoading = false
    }

    // MARK: - Private helpers

    private func clearStats() {
        minValue = 0
        maxValue = 0
        avgValue = 0
        minDisplay = "--"
        avgDisplay = "--"
        maxDisplay = "--"
    }

    private func computeStats(from series: [ChartPoint]) {
        guard !series.isEmpty else {
            clearStats()
            return
        }
        let values = series.map(\.value)
        let min = values.min()!
        let max = values.max()!
        let avg = values.reduce(0, +) / Double(values.count)

        minValue = min
        maxValue = max
        avgValue = avg
        minDisplay = formatMetricValue(min, for: kind)
        maxDisplay = formatMetricValue(max, for: kind)
        avgDisplay = formatMetricValue(avg, for: kind)
    }

    private func loadProcesses() {
        guard let monitor = processMonitor else {
            processRows = []
            return
        }
        let sort: ProcessSort
        switch kind {
        case .cpu:     sort = .cpu
        case .memory:  sort = .memory
        case .network: sort = .network
        default:       sort = .cpu
        }

        guard let topProcesses = try? monitor.top(limit: 8, sort: sort) else {
            processRows = []
            return
        }

        processRows = topProcesses.map { info in
            let value: Double
            let unit: String

            switch kind {
            case .cpu:
                value = info.cpuPercent
                unit = "%"
            case .memory:
                value = Double(info.memoryBytes)
                unit = ""  // formatted as bytes below
            case .network:
                value = Double(info.networkBytesPerSecond)
                unit = ""  // formatted as bytes/s below
            default:
                value = 0
                unit = ""
            }

            return ProcessRow(
                id: Int(info.pid),
                name: info.name,
                value: value,
                unit: unit
            )
        }
        .sorted { $0.value > $1.value }
    }
}

// MARK: - ProcessRow

/// A single process row in the detail view's top-processes list.
public struct ProcessRow: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let value: Double
    public let unit: String

    public init(id: Int, name: String, value: Double, unit: String) {
        self.id = id
        self.name = name
        self.value = value
        self.unit = unit
    }
}
