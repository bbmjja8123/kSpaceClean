import SwiftUI
import MetricsKit
import DesignSystem

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
                Text(String(localized: "Style"))
            } footer: {
                Text(String(localized: "Choose how the menu bar status item renders your metrics."))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Section {
                metricToggles
            } header: {
                Text(String(localized: "Metrics"))
            } footer: {
                Text(String(localized: "Disable metrics you don't want to see. At least one must stay enabled."))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Section {
                if viewModel.perMetricMenuBar {
                    reorderList
                }
                Toggle(String(localized: "Show one icon per metric"), isOn: Binding(
                    get: { viewModel.perMetricMenuBar },
                    set: { viewModel.setPerMetricMenuBar($0) }
                ))
            } header: {
                Text(String(localized: "Multi-icon mode"))
            } footer: {
                Text(String(localized: "Show a separate menu bar icon for each metric, then drag to reorder them."))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        Picker(String(localized: "Style"), selection: Binding(
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
        case .trend: return String(localized: "Trend")
        case .numeric: return String(localized: "Numeric")
        case .minimal: return String(localized: "Minimal")
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

    // MARK: - Multi-icon reorder

    private var reorderList: some View {
        ForEach(viewModel.menuBarOrder, id: \.self) { kind in
            Label(title(for: kind), systemImage: icon(for: kind))
        }
        .onMove { source, destination in
            viewModel.moveMetric(source, to: destination)
        }
    }

    private func title(for kind: MetricKind) -> String {
        switch kind {
        case .cpu: return String(localized: "CPU")
        case .memory: return String(localized: "Memory")
        case .disk: return String(localized: "Disk")
        case .network: return String(localized: "Network")
        case .temperature: return String(localized: "Temperature")
        case .fan: return String(localized: "Fan")
        case .battery: return String(localized: "Battery")
        case .gpu: return String(localized: "GPU")
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
        case .gpu: return "display"
        }
    }
}