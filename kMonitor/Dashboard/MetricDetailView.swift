import SwiftUI
import MetricsKit
import DesignSystem

/// Detail sheet displayed when a metric card is tapped on the dashboard.
///
/// Shows a range picker, trend chart, summary statistics (min/avg/max),
/// and optionally a top-processes table for CPU, Memory, and Network metrics.
/// Free users see a Pro gate overlay.
public struct MetricDetailView: View {
    @StateObject private var viewModel: MetricDetailViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: MetricDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 16) {
            header

            rangePicker

            Divider()

            if viewModel.isLoading {
                loadingView
            } else if !viewModel.isPro {
                proGateView
            } else if viewModel.points.isEmpty {
                emptyView
            } else {
                chartArea
                statsRow
                if viewModel.supportsProcesses && !viewModel.processRows.isEmpty {
                    processesSection
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(String(localized: "Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 400)
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.selectedRange) { _ in
            Task { await viewModel.load() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName(for: viewModel.kind))
                .font(.title2)
                .foregroundStyle(viewModel.chartColor.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.kindTitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if let latest = viewModel.points.last {
                    Text(formatValue(latest.value))
                        .font(AppFont.titleHero)
                        .foregroundStyle(viewModel.chartColor.color)
                } else {
                    Text("--")
                        .font(AppFont.titleHero)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    // MARK: - Range picker

    private var rangePicker: some View {
        Picker(String(localized: "Range"), selection: $viewModel.selectedRange) {
            ForEach(MetricDetailViewModel.Range.allCases) { range in
                Text(range.displayName).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
    }

    // MARK: - Chart

    private var chartArea: some View {
        TrendChart(
            points: viewModel.points,
            lineColor: viewModel.chartColor.color
        )
        .frame(minHeight: 180, maxHeight: 240)
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCard(label: String(localized: "Min"), value: viewModel.minDisplay)
            Spacer()
            statCard(label: String(localized: "Avg"), value: viewModel.avgDisplay)
            Spacer()
            statCard(label: String(localized: "Max"), value: viewModel.maxDisplay)
        }
    }

    private func statCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(AppFont.numberSize)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.bgSecondary)
        )
    }

    // MARK: - Processes

    private var processesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Top Processes"))
                .font(.headline)
                .padding(.top, 4)

            ForEach(viewModel.processRows) { row in
                HStack {
                    Text(row.name)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    Text(formatProcessValue(row))
                        .monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                }
                .font(.callout)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text(String(localized: "Loading\u{2026}"))
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
    }

    private var proGateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.textSecondary)

            Text(String(localized: "Pro Feature"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(String(localized: "Upgrade to Pro to view detailed trends and process breakdowns for this metric."))
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 36))
                .foregroundStyle(Color.textSecondary)

            Text(String(localized: "No Data"))
                .font(.headline)

            Text(String(localized: "No history records found for the selected range. Data collection may have just started."))
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Formatting helpers

    private func formatValue(_ value: Double) -> String {
        formatMetricValue(value, for: viewModel.kind)
    }

    private func formatProcessValue(_ row: ProcessRow) -> String {
        switch viewModel.kind {
        case .cpu:
            return String(format: "%.1f%%", row.value)
        case .memory:
            return formatBytes(UInt64(row.value))
        case .network:
            return "\(formatBytes(UInt64(row.value)))/s"
        default:
            return String(format: "%.1f%@", row.value, row.unit)
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(bytes)
        var unitIndex = 0
        while v >= 1024 && unitIndex < units.count - 1 {
            v /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 { return "\(bytes) B" }
        return String(format: v < 10 ? "%.1f %@" : "%.0f %@", v, units[unitIndex])
    }

    private func iconName(for kind: MetricKind) -> String {
        switch kind {
        case .cpu:         return "cpu"
        case .memory:      return "memorychip"
        case .disk:        return "internaldrive"
        case .network:     return "network"
        case .temperature: return "thermometer"
        case .fan:         return "fan"
        case .battery:     return "battery.100"
        case .gpu:         return "display"
        }
    }
}
