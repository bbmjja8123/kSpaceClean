import SwiftUI

/// One week bucket of reclaimable-bytes history, oldest first.
struct HistoryTrendPoint: Equatable {
    let weekStart: Date
    let reclaimedBytes: Int64
    let scanCount: Int
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var records: [ScanRecord] = []
    @Published var isLoading = false
    /// Record pending delete confirmation (drives the confirmationDialog).
    @Published var recordPendingDelete: ScanRecord?

    private let repository: DuplicateRepositoryProtocol

    init(repository: DuplicateRepositoryProtocol = DuplicateRepositoryCoreData()) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            records = try await repository.loadScanRecords()
        } catch {
            records = []
        }
    }

    func delete(_ record: ScanRecord) async {
        do {
            try await repository.deleteScanRecord(id: record.id)
            records.removeAll { $0.id == record.id }
        } catch {
            // Deleting history is best-effort; keep the record visible so
            // the user can retry rather than silently losing it.
        }
    }

    // MARK: - Aggregations (pure, testable)

    /// Buckets records into the last 8 calendar weeks (oldest → newest).
    /// Weeks with no scans still yield a point (zero bytes) so the chart
    /// shows honest gaps.
    nonisolated static func bucket(
        records: [ScanRecord],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [HistoryTrendPoint] {
        guard let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return []
        }
        var buckets: [Date: (bytes: Int64, scans: Int)] = [:]
        for record in records {
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: record.timestamp)?.start else {
                continue
            }
            let weeksAgo = calendar.dateComponents([.weekOfYear], from: weekStart, to: currentWeekStart).weekOfYear ?? 0
            guard weeksAgo < 8 else { continue }
            let entry = buckets[weekStart, default: (0, 0)]
            let summed = entry.bytes.addingReportingOverflow(record.totalWasteSize)
            buckets[weekStart] = (summed.overflow ? Int64.max : summed.partialValue, entry.scans + 1)
        }
        return (0..<8).compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeekStart) else {
                return nil
            }
            let entry = buckets[start] ?? (0, 0)
            return HistoryTrendPoint(weekStart: start, reclaimedBytes: entry.bytes, scanCount: entry.scans)
        }
        .reversed()
    }

    /// Reclaimable bytes per duplicate category across all records —
    /// drives the distribution legend under the trend chart.
    nonisolated static func categoryDistribution(records: [ScanRecord]) -> [DuplicateCategory: Int64] {
        var totals: [DuplicateCategory: Int64] = [:]
        for record in records {
            for group in record.groups {
                let current = totals[group.category, default: 0]
                let summed = current.addingReportingOverflow(group.totalSize)
                totals[group.category] = summed.overflow ? Int64.max : summed.partialValue
            }
        }
        return totals
    }

    var trendPoints: [HistoryTrendPoint] {
        Self.bucket(records: records)
    }

    var distribution: [DuplicateCategory: Int64] {
        Self.categoryDistribution(records: records)
    }

    var totalReclaimed: Int64 {
        records.reduce(0) { partial, record in
            let sum = partial.addingReportingOverflow(record.totalWasteSize)
            return sum.overflow ? Int64.max : sum.partialValue
        }
    }

    var totalScans: Int { records.count }
}
