import SwiftUI
import MetricsKit

/// Single-metric settings pane. Reused four times in `SettingsView` to
/// provide dedicated CPU / Memory / Disk / Network tabs as required by
/// V1-TODO U5. Each tab hosts:
///   - Enabled toggle (controls whether `MetricsAggregator` samples it)
///   - Menu bar icon style picker (only meaningful when
///     `perMetricMenuBar` is on)
///   - Menu bar display preference (percent / absolute / compact)
///
/// Future per-metric sampling intervals / thresholds will land here too;
/// for v1.1 the per-metric controls read from the existing global
/// `samplingIntervalSeconds` + `enabledKinds` state on the view model.
struct PerMetricTabView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let kind: MetricKind

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { viewModel.enabledKinds.contains(kind) },
                    set: { viewModel.setEnabled($0, for: kind) }
                )) {
                    Label(String(localized: "Enabled"), systemImage: "checkmark.circle")
                }
                .toggleStyle(.switch)
            } header: {
                Text(displayTitle)
            } footer: {
                Text(String(localized: "Disabling stops sampling and hides the metric from the dashboard and menu bar."))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Section {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(Color.textSecondary)
                    Text(String(localized: "Sampling Interval"))
                    Spacer()
                    Text(String(format: "%.1fs", viewModel.samplingIntervalSeconds))
                        .monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                }
            } header: {
                Text(String(localized: "Inherited Setting"))
            } footer: {
                Text(String(localized: "Per-metric override is planned for a future release. Today this metric uses the global sampling interval from the Metrics tab."))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }

    private var displayTitle: String {
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
}