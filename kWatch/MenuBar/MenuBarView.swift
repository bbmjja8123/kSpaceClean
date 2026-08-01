import SwiftUI
import MetricsKit

/// The window-style content shown when the user clicks the kWatch status
/// item. Renders the current metric readings (with an optional trend chart),
/// a mode picker, and navigation actions into the dashboard windows.
public struct MenuBarView: View {
    @ObservedObject public var viewModel: MenuBarViewModel
    @ObservedObject public var appState: AppState
    @ObservedObject public var purchaseState: PurchaseState
    public let onOpenDashboard: () -> Void
    public let onOpenSettings: () -> Void
    public let onOpenHistory: () -> Void
    public let onOpenProcesses: () -> Void
    public let onOpenAlerts: () -> Void

    public init(
        viewModel: MenuBarViewModel,
        appState: AppState,
        purchaseState: PurchaseState,
        onOpenDashboard: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenHistory: @escaping () -> Void,
        onOpenProcesses: @escaping () -> Void,
        onOpenAlerts: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.appState = appState
        self.purchaseState = purchaseState
        self.onOpenDashboard = onOpenDashboard
        self.onOpenSettings = onOpenSettings
        self.onOpenHistory = onOpenHistory
        self.onOpenProcesses = onOpenProcesses
        self.onOpenAlerts = onOpenAlerts
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if viewModel.mode == .trend {
                MiniTrendChart(values: viewModel.cpuHistory)
                    .frame(height: 28)
            }
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                MetricMenuRow(title: "CPU", value: "\(Int(viewModel.cpuPercent))%", icon: "cpu")
                MetricMenuRow(title: "Memory", value: "\(Int(viewModel.memoryPercent))%", icon: "memorychip")
                MetricMenuRow(title: "Disk", value: "\(Int(viewModel.diskPercent))%", icon: "internaldrive")
                MetricMenuRow(title: "Network", value: formatBytes(viewModel.networkBytesPerSecond) + "/s", icon: "network")
            }
            modePicker
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                Button("Open Dashboard…", action: onOpenDashboard)
                Button("History…", action: onOpenHistory)
                Button("Processes…", action: onOpenProcesses)
                Button("Alerts…", action: onOpenAlerts)
                Button("Settings…", action: onOpenSettings)
            }
            Divider()
            Text("kWatch").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 280)
    }

    private var header: some View {
        HStack {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
            Text("kWatch").font(.headline)
            Spacer()
            if purchaseState.isPro {
                Text("Pro").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: Binding(
            get: { viewModel.mode },
            set: { viewModel.setMode($0) }
        )) {
            Text("Trend").tag(MenuBarMode.trend)
            Text("Numeric").tag(MenuBarMode.numeric)
            Text("Minimal").tag(MenuBarMode.minimal)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        return String(format: value < 10 ? "%.1f %@" : "%.0f %@", value, units[unitIndex])
    }
}
