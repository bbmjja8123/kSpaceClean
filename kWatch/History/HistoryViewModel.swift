import Foundation
import Combine
import MetricsKit

// MARK: - ChartPoint

/// A single x/y data point for the trend chart.
///
/// `date` provides the x-axis position; `value` is the numeric reading.
/// `Identifiable` by `date` so SwiftUI can diff collections; callers
/// must ensure unique timestamps per series.
public struct ChartPoint: Sendable, Equatable, Identifiable {
    public let id: Date
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.id = date
        self.date = date
        self.value = value
    }
}

// MARK: - HistoryRange

/// The time window for which history data is loaded.
public enum HistoryRange: String, CaseIterable, Sendable, Equatable {
    case hours24
    case days7
    case days30

    /// The exact interval ending at a caller-supplied reference date.
    public func dateInterval(endingAt end: Date) -> DateInterval {
        let duration: TimeInterval
        switch self {
        case .hours24:
            duration = 24 * 60 * 60
        case .days7:
            duration = 7 * 24 * 60 * 60
        case .days30:
            duration = 30 * 24 * 60 * 60
        }
        return DateInterval(start: end.addingTimeInterval(-duration), end: end)
    }

    /// The interval ending now, used by production callers.
    public var dateInterval: DateInterval {
        dateInterval(endingAt: Date())
    }
}

// MARK: - HistoryViewModel

/// Main-actor-bound view model that loads metric history from the repository,
/// downsamples it for display, and exposes formatted summary values.
///
/// Free users see a Pro gate and the repository is never queried.
/// Pro users can select any range and any metric kind; large series are
/// downsampled to at most 500 points using min/max bucket preservation.
@MainActor
public final class HistoryViewModel: ObservableObject {
    // MARK: Published state

    /// Downsampled chart points ready for rendering.
    @Published public private(set) var points: [ChartPoint] = []

    /// `true` while the repository is being queried.
    @Published public private(set) var isLoading = false

    /// A user-presentable error message, or `nil`.
    @Published public private(set) var errorMessage: String?

    /// The currently selected time range.
    @Published public var selectedRange: HistoryRange = .hours24

    /// The currently selected metric kind.
    @Published public var selectedMetric: MetricKind = .cpu

    /// Whether the user is locked out because they are not Pro.
    @Published public private(set) var isLocked = true

    /// `true` when the loaded series contains no data points.
    @Published public private(set) var isEmpty = false

    // MARK: Summary values (raw)

    @Published public private(set) var minValue: Double?
    @Published public private(set) var maxValue: Double?
    @Published public private(set) var averageValue: Double?

    // MARK: Summary values (formatted)

    @Published public private(set) var minDisplay: String?
    @Published public private(set) var maxDisplay: String?
    @Published public private(set) var averageDisplay: String?

    // MARK: Dependencies

    private let repository: HistoryRepositoryProtocol
    private let purchaseState: PurchaseState
    private let now: @Sendable () -> Date
    private var cancellables = Set<AnyCancellable>()
    private var hasAppeared = false

    // MARK: Init

    public init(
        repository: HistoryRepositoryProtocol,
        purchaseState: PurchaseState,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.purchaseState = purchaseState
        self.now = now
        self.isLocked = !purchaseState.isPro

        purchaseState.$isPro
            .removeDuplicates()
            .sink { [weak self] isPro in
                guard let self else { return }
                self.isLocked = !isPro
                if !isPro {
                    self.isLoading = false
                    self.errorMessage = nil
                    self.points = []
                    self.isEmpty = true
                    self.clearSummaries()
                } else if self.hasAppeared {
                    Task { @MainActor [weak self] in
                        await self?.load()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Public API

    /// Load history for the current `selectedRange` and `selectedMetric`.
    ///
    /// Free users are gated *before* calling the repository so that no
    /// persistence I/O occurs for unentitled users.
    public func load() async {
        hasAppeared = true
        guard purchaseState.isPro else {
            isLocked = true
            isLoading = false
            errorMessage = nil
            points = []
            isEmpty = true
            clearSummaries()
            return
        }

        isLocked = false
        isLoading = true
        errorMessage = nil
        isEmpty = false

        do {
            let since = selectedRange.dateInterval(endingAt: now()).start
            let snapshots = try repository.samples(since: since)

            let fullSeries = snapshots.compactMap { snapshot -> ChartPoint? in
                guard let value = extractDouble(
                    from: snapshot.values[selectedMetric],
                    for: selectedMetric
                ) else {
                    return nil
                }
                return ChartPoint(date: snapshot.timestamp, value: value)
            }
            .sorted { $0.date < $1.date }

            computeSummaries(from: fullSeries)
            points = downsample(points: fullSeries, maxCount: 500)
            isEmpty = fullSeries.isEmpty
        } catch {
            errorMessage = error.localizedDescription
            points = []
            isEmpty = true
            clearSummaries()
        }

        isLoading = false
    }

    // MARK: Private helpers

    private func clearSummaries() {
        minValue = nil
        maxValue = nil
        averageValue = nil
        minDisplay = nil
        maxDisplay = nil
        averageDisplay = nil
    }

    private func computeSummaries(from points: [ChartPoint]) {
        guard !points.isEmpty else {
            clearSummaries()
            return
        }
        let values = points.map(\.value)
        minValue = values.min()
        maxValue = values.max()
        averageValue = values.reduce(0, +) / Double(values.count)

        let metric = selectedMetric
        minDisplay = minValue.map { formatMetricValue($0, for: metric) }
        maxDisplay = maxValue.map { formatMetricValue($0, for: metric) }
        averageDisplay = averageValue.map { formatMetricValue($0, for: metric) }
    }
}

// MARK: - Internal helpers

/// Extract the numeric representation expected for a metric kind.
/// Mismatched, textual, and unavailable values are omitted rather than plotted as zero.
internal func extractDouble(from value: MetricValue?, for kind: MetricKind) -> Double? {
    guard let value else { return nil }
    switch (kind, value) {
    case (.cpu, .percentage(let number)),
         (.memory, .percentage(let number)),
         (.disk, .percentage(let number)),
         (.battery, .percentage(let number)):
        return number
    case (.network, .bytesPerSecond(let bytesPerSecond)):
        return Double(bytesPerSecond)
    case (.temperature, .degreesCelsius(let degrees)):
        return degrees
    case (.fan, .revolutionsPerMinute(let rpm)):
        return rpm
    default:
        return nil
    }
}

/// Downsample a sorted (ascending-by-date) series to at most `maxCount` points
/// using min/max buckets so transient spikes are preserved.
///
/// Each bucket contributes at most two points (the minimum and maximum values),
/// keeping extremes visible. Empty and singleton arrays pass through unchanged.
///
/// - Precondition: `points` should be sorted in ascending chronological order.
internal func downsample(points: [ChartPoint], maxCount: Int) -> [ChartPoint] {
    guard points.count > maxCount, maxCount >= 2 else { return points }

    let bucketCount = maxCount / 2
    let bucketSize = max(1, Int(ceil(Double(points.count) / Double(bucketCount))))
    var result: [ChartPoint] = []
    var i = 0

    while i < points.count {
        let end = min(i + bucketSize, points.count)
        let slice = points[i..<end]

        if let minP = slice.min(by: { $0.value < $1.value }),
           let maxP = slice.max(by: { $0.value < $1.value }) {
            // Preserve chronological order within the bucket.
            if minP.date <= maxP.date {
                result.append(minP)
                if minP.date != maxP.date { result.append(maxP) }
            } else {
                result.append(maxP)
                result.append(minP)
            }
        } else if let single = slice.first {
            result.append(single)
        }

        i = end
    }

    // Trim if we overshot due to many buckets with distinct min/max.
    if result.count > maxCount {
        result = Array(result.prefix(maxCount))
    }

    return result
}

/// Format a `Double` value for display based on the `MetricKind`.
///
/// This lives in the view model layer so that `TrendChart` and `HistoryView`
/// never contain formatting logic.
internal func formatMetricValue(_ value: Double, for kind: MetricKind) -> String {
    switch kind {
    case .cpu, .memory, .disk, .battery:
        return "\(Int(round(value)))%"
    case .network:
        let bytes = UInt64(value)
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(bytes)
        var unitIndex = 0
        while v >= 1024, unitIndex < units.count - 1 {
            v /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 { return "\(bytes) B/s" }
        return String(format: v < 10 ? "%.1f %@/s" : "%.0f %@/s", v, units[unitIndex])
    case .temperature:
        return "\(Int(round(value)))°C"
    case .fan:
        return "\(Int(round(value))) RPM"
    }
}
