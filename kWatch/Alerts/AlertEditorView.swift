import SwiftUI
import MetricsKit
import DesignSystem

/// A form for creating or editing a threshold alert.
///
/// Fields: metric kind, condition operator, threshold value with unit label,
/// and cooldown in seconds.  Save is disabled when validation fails.
struct AlertEditorView: View {
    @ObservedObject var viewModel: AlertsViewModel
    let alert: MetricAlert

    @State private var kind: MetricKind
    @State private var op: MetricAlert.Operator
    @State private var thresholdText: String
    @State private var cooldownText: String

    private static let operatorOptions: [MetricAlert.Operator] = [.above, .below]

    init(viewModel: AlertsViewModel, alert: MetricAlert) {
        self.viewModel = viewModel
        self.alert = alert
        _kind = State(initialValue: alert.kind)
        _op = State(initialValue: alert.op)
        _thresholdText = State(initialValue: "\(Int(alert.threshold))")
        _cooldownText = State(initialValue: "\(alert.cooldownSeconds)")
    }

    // MARK: - Validation

    private var isValid: Bool {
        guard let threshold = Double(thresholdText), threshold > 0 else { return false }
        guard let cooldown = Int(cooldownText), cooldown > 0 else { return false }
        return true
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Text(viewModel.isEditingNewAlert ? "New Alert" : "Edit Alert")
                .font(.headline)
                .padding(.top)

            Form {
                metricPicker
                operatorPicker
                thresholdField
                cooldownField
            }
            .formStyle(.grouped)

            buttons
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Form fields

    private var metricPicker: some View {
        Picker("Metric", selection: $kind) {
            ForEach(MetricKind.allCases, id: \.self) { kind in
                Text(kind.rawValue.capitalized).tag(kind)
            }
        }
    }

    private var operatorPicker: some View {
        Picker("Condition", selection: $op) {
            ForEach(Self.operatorOptions, id: \.self) { op in
                Text(op == .above ? "Above" : "Below").tag(op)
            }
        }
    }

    private var thresholdField: some View {
        HStack {
            Text("Threshold")
            Spacer()
            TextField("80", text: $thresholdText)
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
            Text(unitLabel(for: kind))
                .foregroundColor(Color.textSecondary)
                .frame(width: 40, alignment: .leading)
        }
    }

    private var cooldownField: some View {
        HStack {
            Text("Cooldown (s)")
            Spacer()
            TextField("300", text: $cooldownText)
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Action buttons

    private var buttons: some View {
        HStack {
            Button("Cancel") {
                viewModel.isPresentingEditor = false
                viewModel.editingAlert = nil
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Save") {
                guard
                    let threshold = Double(thresholdText),
                    let cooldown = Int(cooldownText),
                    threshold > 0, cooldown > 0
                else { return }

                let updated = MetricAlert(
                    id: alert.id,
                    kind: kind,
                    op: op,
                    threshold: threshold,
                    isEnabled: alert.isEnabled,
                    cooldownSeconds: cooldown,
                    lastTriggeredAt: alert.lastTriggeredAt
                )
                viewModel.save(updated)
            }
            .disabled(!isValid)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Helpers

    private func unitLabel(for kind: MetricKind) -> String {
        switch kind {
        case .cpu, .memory, .disk, .battery:
            return "%"
        case .network:
            return "B/s"
        case .temperature:
            return "°C"
        case .fan:
            return "RPM"
        }
    }
}
