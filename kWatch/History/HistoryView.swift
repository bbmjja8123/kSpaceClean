import SwiftUI
import MetricsKit
import DesignSystem

/// The history trends screen, showing a range selector, metric picker,
/// summary statistics, and the trend chart.
///
/// Free users see a Pro gate instead of chart content. Pro users can
/// select 24-hour, 7-day, or 30-day windows for any supported metric.
/// Loading, error, and empty states are handled explicitly.
public struct HistoryView: View {
    @ObservedObject private var viewModel: HistoryViewModel
    private let onBack: (() -> Void)?
    private let onOpenPaywall: (() -> Void)?

    public init(
        viewModel: HistoryViewModel,
        onBack: (() -> Void)? = nil,
        onOpenPaywall: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onOpenPaywall = onOpenPaywall
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: Top bar
            topBar
                .padding(.horizontal)
                .padding(.top, 8)

            Divider()
                .padding(.top, 8)

            // MARK: Content
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.selectedRange) { _ in
            Task { await viewModel.load() }
        }
        .onChange(of: viewModel.selectedMetric) { _ in
            Task { await viewModel.load() }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                onBack?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Dashboard")
                }
            }
            .buttonStyle(.plain)
            .help("Return to Dashboard")

            Spacer()

            Text("History")
                .font(.headline)
                .foregroundStyle(Color.textSecondary)

            Spacer()

            Picker("Range", selection: $viewModel.selectedRange) {
                Text("24h").tag(HistoryRange.hours24)
                Text("7d").tag(HistoryRange.days7)
                Text("30d").tag(HistoryRange.days30)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Picker("Metric", selection: $viewModel.selectedMetric) {
                ForEach(MetricKind.allCases, id: \.self) { kind in
                    Text(metricLabel(kind)).tag(kind)
                }
            }
            .frame(width: 140)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLocked {
            proGateView
        } else if viewModel.isLoading {
            loadingView
        } else if let errorMessage = viewModel.errorMessage {
            errorView(message: errorMessage)
        } else if viewModel.isEmpty {
            emptyView
        } else {
            dataView
        }
    }

    // MARK: Pro gate

    private var proGateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.textSecondary)

            Text("Metric History")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Upgrade to Pro to view historical trends, charts, and detailed summaries for all metrics.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Text("Free users can monitor live CPU, Memory, Disk, and Network.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary.opacity(0.6))
                .multilineTextAlignment(.center)

            Button("View kWatch Pro") {
                onOpenPaywall?()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading history\u{2026}")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
    }

    // MARK: Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.brandAccent)

            Text("Failed to Load History")
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Retry") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
    }

    // MARK: Empty

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 36))
                .foregroundStyle(Color.textSecondary)

            Text("No Data")
                .font(.headline)

            Text("No history records found for the selected range and metric. Data collection may have just started.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: Data view (chart + summaries)

    private var dataView: some View {
        VStack(spacing: 12) {
            // Summary row
            HStack(spacing: 0) {
                summaryItem(label: "Min", value: viewModel.minDisplay)
                Spacer()
                summaryItem(label: "Average", value: viewModel.averageDisplay)
                Spacer()
                summaryItem(label: "Max", value: viewModel.maxDisplay)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            // Chart
            TrendChart(
                points: viewModel.points,
                lineColor: chartColor(for: viewModel.selectedMetric),
                fillColor: chartColor(for: viewModel.selectedMetric).opacity(0.08)
            )
            .frame(minHeight: 180, maxHeight: 240)
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func summaryItem(label: String, value: String?) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary.opacity(0.6))
            Text(value ?? "--")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textPrimary)
        }
    }

    // MARK: - Helpers

    private func metricLabel(_ kind: MetricKind) -> String {
        switch kind {
        case .cpu:         return "CPU"
        case .memory:      return "Memory"
        case .disk:        return "Disk"
        case .network:     return "Network"
        case .temperature: return "Temperature"
        case .fan:         return "Fan"
        case .battery:     return "Battery"
        }
    }

    private func chartColor(for kind: MetricKind) -> Color {
        switch kind {
        case .cpu:         return .blue
        case .memory:      return .green
        case .disk:        return .orange
        case .network:     return .purple
        case .temperature: return .red
        case .fan:         return .yellow
        case .battery:     return .green
        }
    }
}

// MARK: - Preview

struct HistoryView_Data_Previews: PreviewProvider {
    static var previews: some View {
        let vm = HistoryViewModel(
            repository: InMemoryHistoryRepository(snapshots: {
                let now = Date()
                return (0..<100).map { i in
                    MetricSnapshot(
                        timestamp: now.addingTimeInterval(Double(-i * 60)),
                        values: [.cpu: .percentage(Double.random(in: 20...90))],
                        availability: [:]
                    )
                }
            }()),
            purchaseState: {
                let ps = PurchaseState()
                ps.update(isPro: true)
                return ps
            }()
        )
        HistoryView(viewModel: vm)
            .frame(width: 700, height: 400)
    }
}

struct HistoryView_Locked_Previews: PreviewProvider {
    static var previews: some View {
        let vm = HistoryViewModel(
            repository: InMemoryHistoryRepository(),
            purchaseState: PurchaseState()
        )
        HistoryView(viewModel: vm)
            .frame(width: 700, height: 400)
    }
}

struct HistoryView_Empty_Previews: PreviewProvider {
    static var previews: some View {
        let vm = HistoryViewModel(
            repository: InMemoryHistoryRepository(),
            purchaseState: {
                let ps = PurchaseState()
                ps.update(isPro: true)
                return ps
            }()
        )
        HistoryView(viewModel: vm)
            .frame(width: 700, height: 400)
    }
}
