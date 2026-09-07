import SwiftUI
import Charts
import DesignSystem

/// Weekly reclaimable-bytes bar chart plus the all-time header stats.
/// Swift Charts is available from macOS 13, so no #available gating.
struct HistoryTrendChart: View {
    let points: [HistoryTrendPoint]
    let distribution: [DuplicateCategory: Int64]
    let totalScans: Int
    let totalReclaimed: Int64

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("History")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        Text(ByteCountFormatter.string(fromByteCount: totalReclaimed, countStyle: .file))
                            .font(.title3).bold()
                            .foregroundColor(.textPrimary)
                        Text("reclaimed across scans")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(totalScans)")
                            .font(.title3).bold()
                            .foregroundColor(.textPrimary)
                        Text("scans")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                    }
                }

                if points.contains(where: { $0.reclaimedBytes > 0 }) {
                    Chart(points, id: \.weekStart) { point in
                        BarMark(
                            x: .value("Week", point.weekStart, unit: .weekOfYear),
                            y: .value("Reclaimed", point.reclaimedBytes)
                        )
                        .foregroundStyle(Color.brandPrimary.gradient)
                        .cornerRadius(3)
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let bytes = value.as(Int64.self) {
                                    Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .font(.caption2)
                        }
                    }
                    .frame(height: 120)
                } else {
                    Text("Scan history for the last 8 weeks will appear here.")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, AppSpacing.lg)
                }

                if !distribution.isEmpty {
                    distributionLegend
                }
            }
            .padding(AppSpacing.lg)
        }
    }

    /// Byte-weighted category breakdown, largest first.
    private var distributionLegend: some View {
        let total = distribution.values.reduce(Int64(0)) { $0 + $1 }
        let sorted = distribution.sorted { $0.value > $1.value }
        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ForEach(sorted, id: \.key) { category, bytes in
                HStack(spacing: AppSpacing.sm) {
                    Circle()
                        .fill(category.color)
                        .frame(width: 7, height: 7)
                    Text(category.displayName)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if total > 0 {
                        Text("\(Int((Double(bytes) / Double(total) * 100).rounded()))%")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}
