import SwiftUI
import MetricsKit

/// Metric-specific settings pane: per-metric enable/disable toggles and
/// global sampling interval slider. All mutations go through
/// `SettingsViewModel` so changes are persisted immediately.
struct MetricSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                samplingRow
            } header: {
                Text(String(localized: "Sampling Interval"))
            } footer: {
                Text(String(localized: "Higher rates consume more CPU and battery. The default 2s is a good balance."))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Section {
                metricToggles
            } header: {
                Text(String(localized: "Enabled Metrics"))
            } footer: {
                Text(String(localized: "Disable metrics you don't want to monitor. At least one must stay enabled."))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }

    // MARK: - Sampling interval

    private var samplingRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(localized: "Interval"))
                    .font(.headline)
                Spacer()
                Text(String(format: "%.1fs", viewModel.samplingIntervalSeconds))
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }
            Slider(
                value: Binding(
                    get: { viewModel.samplingIntervalSeconds },
                    set: { viewModel.setSamplingInterval($0) }
                ),
                in: 0.5...10.0,
                step: 0.5
            )
        }
    }

    // MARK: - Per-metric toggles

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
