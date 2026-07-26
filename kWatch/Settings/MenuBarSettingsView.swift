import SwiftUI
import MetricsKit

/// Menu Bar settings pane: presentation mode picker and per-metric-kind
/// enable toggles. All mutations go through `SettingsViewModel` so they are
/// persisted immediately to the App Group preferences.
struct MenuBarSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                modePicker
            } header: {
                Text("Style")
            } footer: {
                Text("Choose how the menu bar status item renders your metrics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                metricToggles
            } header: {
                Text("Metrics")
            } footer: {
                Text("Disable metrics you don't want to see. At least one must stay enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        Picker("Style", selection: Binding(
            get: { viewModel.menuBarMode },
            set: { viewModel.setMenuBarMode($0) }
        )) {
            ForEach(MenuBarMode.allCases, id: \.self) { mode in
                Text(label(for: mode)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func label(for mode: MenuBarMode) -> String {
        switch mode {
        case .trend: return "Trend"
        case .numeric: return "Numeric"
        case .minimal: return "Minimal"
        }
    }

    // MARK: - Metric toggles

    private var metricToggles: some View {
        ForEach(MetricKind.allCases, id: \.self) { kind in
            Toggle(isOn: Binding(
                get: { viewModel.enabledKinds.contains(kind) },
                set: { viewModel.setEnabled($0, for: kind) }
            )) {
                Label(title(for: kind), systemImage: icon(for: kind))
            }
            .toggleStyle(.switch)
        }
    }

    private func title(for kind: MetricKind) -> String {
        switch kind {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .network: return "Network"
        case .temperature: return "Temperature"
        case .fan: return "Fan"
        case .battery: return "Battery"
        }
    }

    private func icon(for kind: MetricKind) -> String {
        switch kind {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .temperature: return "thermometer"
        case .fan: return "fan.fill"
        case .battery: return "battery.100"
        }
    }
}