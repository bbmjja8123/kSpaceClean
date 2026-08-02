import SwiftUI
import MetricsKit
import DesignSystem

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

    /// Fired when the user taps a Pro-gated (locked) metric row so the
    /// hosting scene can present the paywall sheet.
    public let onOpenPaywall: (() -> Void)?

    public init(
        viewModel: MenuBarViewModel,
        appState: AppState,
        purchaseState: PurchaseState,
        onOpenDashboard: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenHistory: @escaping () -> Void,
        onOpenProcesses: @escaping () -> Void,
        onOpenAlerts: @escaping () -> Void,
        onOpenPaywall: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.appState = appState
        self.purchaseState = purchaseState
        self.onOpenDashboard = onOpenDashboard
        self.onOpenSettings = onOpenSettings
        self.onOpenHistory = onOpenHistory
        self.onOpenProcesses = onOpenProcesses
        self.onOpenAlerts = onOpenAlerts
        self.onOpenPaywall = onOpenPaywall
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            QuickToggleBar()
                .padding(.horizontal, 4)
            Divider()
            metricList
            Divider()
            modePicker
            Divider()
            footerActions
            Text("kWatch v1.0").font(.caption2).foregroundStyle(Color.textSecondary)
        }
        .padding(12)
        .frame(width: 360)
    }

    private var metricList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(MetricKind.menuBarDisplayOrder, id: \.self) { kind in
                metricRow(for: kind)
            }
        }
    }

    @ViewBuilder
    private func metricRow(for kind: MetricKind) -> some View {
        let row = makeRow(for: kind)
        MetricMenuRow(
            title: row.title,
            value: row.value,
            icon: row.icon,
            isLocked: row.isLocked,
            onTap: row.isLocked ? { onOpenPaywall?() } : nil
        )
    }

    private func makeRow(for kind: MetricKind) -> (title: String, value: String, icon: String, isLocked: Bool) {
        switch kind {
        case .cpu:
            return ("CPU", "\(Int(viewModel.cpuPercent))%", "cpu", false)
        case .memory:
            return ("Memory", "\(Int(viewModel.memoryPercent))%", "memorychip", false)
        case .disk:
            return ("Disk", "\(Int(viewModel.diskPercent))%", "internaldrive", false)
        case .network:
            let kbps = Double(viewModel.networkBytesSent + viewModel.networkBytesReceived) / 1024
            return ("Network", String(format: "%.0f KB/s", kbps), "network", false)
        case .temperature:
            let v = viewModel.temperatureCelsius
            return ("Temperature", v.map { String(format: "%.0f°C", $0) } ?? "—",
                    "thermometer.medium", !purchaseState.isPro)
        case .fan:
            let v = viewModel.fanRPM
            return ("Fan", v.map { "\($0) RPM" } ?? "—",
                    "fan.fill", !purchaseState.isPro)
        case .battery:
            let v = viewModel.batteryPercent
            return ("Battery", v.map { "\(Int($0))%" } ?? "—",
                    "battery.100", !purchaseState.isPro)
        }
    }

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Open Dashboard…", action: onOpenDashboard)
            Button("History…", action: onOpenHistory)
            Button("Processes…", action: onOpenProcesses)
            Button("Alerts…", action: onOpenAlerts)
            Button("Settings…", action: onOpenSettings)
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
            Text("kWatch").font(.headline)
            Spacer()
            if purchaseState.isPro {
                Text("Pro").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.brandSecondary.opacity(0.15))
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
}
