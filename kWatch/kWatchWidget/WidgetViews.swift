//
//  WidgetViews.swift
//  kWatchWidget
//
//  SwiftUI views for the System Status widget. Renders four mini-cards
//  (CPU / memory / disk / network) in small, medium, and large families.
//  Larger families add sparkline / temperature / fan rows. macOS 14+ adds
//  an interactive `Button(intent:)` that fires `OpenDashboardIntent`.
//
//  All visual primitives here are plain `Text` + `RoundedRectangle` — the
//  widget must render without any asset bundle dependencies.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Intent stub

/// Opens the kWatch dashboard in the main app.
///
/// This is a deliberately minimal stub. The main app's intents module
/// (Task 21) will flesh out `perform()` with an `OpensIntent`-style helper
/// that launches the app and routes to the dashboard tab.
public struct OpenDashboardIntent: AppIntent {
    public static var title: LocalizedStringResource = "Open kWatch Dashboard"
    public static var description = IntentDescription(
        "Opens the kWatch dashboard so you can review current metrics."
    )

    public init() {}

    public func perform() async throws -> some IntentResult {
        // Intentionally a no-op. The full implementation lives in
        // `kWatchIntents/OpenDashboardIntent.swift` (Task 21). For the widget
        // surface, we just need a stable type the view can reference.
        return .result()
    }
}

// MARK: - Entry view

/// Top-level entry view. Dispatches to the appropriate family layout.
public struct SystemStatusWidgetView: View {
    public let entry: SystemStatusEntry

    @Environment(\.widgetFamily) private var family

    public init(entry: SystemStatusEntry) {
        self.entry = entry
    }

    public var body: some View {
        switch family {
        case .systemSmall:
            SmallStatusView(entry: entry)
        case .systemMedium:
            MediumStatusView(entry: entry)
        case .systemLarge:
            LargeStatusView(entry: entry)
        default:
            SmallStatusView(entry: entry)
        }
    }
}

// MARK: - Small family

/// 2x2 grid of mini-cards. The simplest useful view: CPU, MEM, DISK, NET.
struct SmallStatusView: View {
    let entry: SystemStatusEntry

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                MiniCard(metric: .cpu, snapshot: entry.snapshot)
                MiniCard(metric: .memory, snapshot: entry.snapshot)
            }
            HStack(spacing: 6) {
                MiniCard(metric: .disk, snapshot: entry.snapshot)
                MiniCard(metric: .network, snapshot: entry.snapshot)
            }
        }
        .padding(8)
        .modifier(StaleBadgeModifier(state: entry.state))
    }
}

// MARK: - Medium family

/// Top row: 4 mini-cards. Bottom row: a sparkline placeholder + label.
struct MediumStatusView: View {
    let entry: SystemStatusEntry

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                MiniCard(metric: .cpu, snapshot: entry.snapshot)
                MiniCard(metric: .memory, snapshot: entry.snapshot)
                MiniCard(metric: .disk, snapshot: entry.snapshot)
                MiniCard(metric: .network, snapshot: entry.snapshot)
            }
            SparklinePlaceholder()
                .frame(height: 28)
            HStack {
                Text(lastUpdatedLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                OpenDashboardButton()
            }
        }
        .padding(8)
        .modifier(StaleBadgeModifier(state: entry.state))
    }

    private var lastUpdatedLabel: String {
        guard let snapshot = entry.snapshot else { return "No data" }
        return "Updated \(snapshot.timestamp.formatted(date: .omitted, time: .standard))"
    }
}

// MARK: - Large family

/// Full status: 4 mini-cards, temperature + fan rows (when available),
/// battery, last-updated label, and the open button.
struct LargeStatusView: View {
    let entry: SystemStatusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                MiniCard(metric: .cpu, snapshot: entry.snapshot)
                MiniCard(metric: .memory, snapshot: entry.snapshot)
                MiniCard(metric: .disk, snapshot: entry.snapshot)
                MiniCard(metric: .network, snapshot: entry.snapshot)
            }

            if let snapshot = entry.snapshot {
                if snapshot.temperatureAvailable, let temp = snapshot.temperatureCelsius {
                    SensorRow(label: "Temperature", value: String(format: "%.0f °C", temp))
                }
                if snapshot.fanAvailable, let rpm = snapshot.fanRPM {
                    SensorRow(label: "Fan", value: String(format: "%.0f RPM", rpm))
                }
                if snapshot.batteryAvailable, let battery = snapshot.batteryPercent {
                    SensorRow(label: "Battery", value: String(format: "%.0f%%", battery))
                }
            }

            Spacer(minLength: 0)

            HStack {
                Text(lastUpdatedLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                OpenDashboardButton()
            }
        }
        .padding(8)
        .modifier(StaleBadgeModifier(state: entry.state))
    }

    private var lastUpdatedLabel: String {
        guard let snapshot = entry.snapshot else { return "No data" }
        return "Updated \(snapshot.timestamp.formatted(date: .omitted, time: .standard))"
    }
}

// MARK: - Reusable building blocks

/// One mini-card. Shows a label + a value, or "N/A" when the metric is not
/// available on this hardware.
struct MiniCard: View {
    enum Metric {
        case cpu, memory, disk, network

        var label: String {
            switch self {
            case .cpu: return "CPU"
            case .memory: return "MEM"
            case .disk: return "DISK"
            case .network: return "NET"
            }
        }
    }

    let metric: Metric
    let snapshot: SharedSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(valueText)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.background.secondary)
        )
    }

    private var valueText: String {
        guard let snapshot else { return "N/A" }
        switch metric {
        case .cpu:
            return snapshot.cpuAvailable ? String(format: "%.0f%%", snapshot.cpuPercent) : "N/A"
        case .memory:
            return snapshot.memoryAvailable ? String(format: "%.0f%%", snapshot.memoryPercent) : "N/A"
        case .disk:
            return snapshot.diskAvailable ? String(format: "%.0f%%", snapshot.diskPercent) : "N/A"
        case .network:
            guard snapshot.networkAvailable else { return "N/A" }
            return formatBytes(snapshot.networkBytesPerSecond) + "/s"
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// Sparkline placeholder. Real implementation in Task 14 history/charts will
/// be plumbed here later; for now a labelled rectangle so the medium/large
/// families have a stable layout.
struct SparklinePlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(.secondary, lineWidth: 1)
            .overlay(
                Text("Sparkline (coming soon)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            )
    }
}

/// Two-column sensor row for the large family.
struct SensorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }
}

/// Stale badge overlay. Shown in the top-trailing corner of every family
/// when the snapshot is older than the freshness threshold. Skipped on
/// `.placeholder` because the placeholder already shows the "Open" prompt.
struct StaleBadgeModifier: ViewModifier {
    let state: WidgetState

    func body(content: Content) -> some View {
        if state == .stale {
            content.overlay(alignment: .topTrailing) {
                Text("Stale")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.orange.opacity(0.85))
                    )
                    .foregroundStyle(.white)
                    .padding(4)
            }
        } else {
            content
        }
    }
}

/// macOS 14 interactive "Open" button. On macOS 13, this is a no-op label
/// because `Button(intent:)` requires macOS 14.
struct OpenDashboardButton: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            // Widgets get a deep link + an interactive button. The button
            // launches the intent on macOS 14; the deep link guarantees the
            // app opens even if intents are not delivered (e.g. notification
            // center out-of-process).
            Button(intent: OpenDashboardIntent()) {
                Label("Open", systemImage: "arrow.up.right.square")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .widgetURL(URL(string: "kwatch://open"))
        } else {
            // macOS 13: only the deep link is available; widgets cannot host
            // `Button(intent:)` actions. We render an empty placeholder so
            // the HStack keeps its layout.
            EmptyView()
        }
    }
}