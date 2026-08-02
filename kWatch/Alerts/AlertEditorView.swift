import SwiftUI
import MetricsKit
import DesignSystem

/// A per-metric configuration form for threshold alerts.
///
/// One section per metric with an on/off toggle, a condition operator, and a
/// threshold slider.  Temperature / fan / battery are Pro metrics: for free
/// users they appear as visible but locked sections (lock indicator and
/// disabled controls).  Trigger frequency is capped at one alert per metric
/// every 5 minutes by `AlertEvaluator`; the shared cooldown control lets the
/// user configure a longer period.
struct AlertEditorView: View {
    @ObservedObject var viewModel: AlertsViewModel
    let alert: MetricAlert

    @State private var drafts: [MetricKind: MetricDraft]
    @State private var sharedCooldown: Int

    private static let metricOrder: [MetricKind] = MetricKind.menuBarDisplayOrder
    private static let proKinds: Set<MetricKind> = [.temperature, .fan, .battery]
    nonisolated fileprivate static let cooldownDefault = 300
    private static let cooldownRange = 300...86_400

    init(viewModel: AlertsViewModel, alert: MetricAlert) {
        self.viewModel = viewModel
        self.alert = alert

        var initialDrafts: [MetricKind: MetricDraft] = [:]
        var maxCooldown = Self.cooldownDefault
        for kind in Self.metricOrder {
            let existing = viewModel.alerts.first { $0.kind == kind }
            let draft = MetricDraft(existing: existing, kind: kind)
            initialDrafts[kind] = draft
            maxCooldown = max(maxCooldown, draft.cooldownSeconds)
        }
        _drafts = State(initialValue: initialDrafts)
        _sharedCooldown = State(initialValue: maxCooldown)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Alert Settings")
                .font(AppFont.title3)
                .padding(.top, AppSpacing.md)

            Form {
                cooldownSection
                metricSections
            }
            .formStyle(.grouped)

            buttons
        }
        .frame(width: 460, height: 520)
    }

    // MARK: - Cooldown

    private var cooldownSection: some View {
        Section {
            Stepper(value: $sharedCooldown, in: Self.cooldownRange, step: 60) {
                HStack {
                    Text("Cooldown")
                        .font(AppFont.body)
                    Spacer()
                    Text(cooldownLabel)
                        .font(AppFont.callout)
                        .foregroundColor(Color.textSecondary)
                }
            }
            Text("At most one alert per metric every 5 minutes. A longer cooldown is honored.")
                .font(AppFont.caption)
                .foregroundColor(Color.textSecondary)
        }
    }

    private var cooldownLabel: String {
        if sharedCooldown % 60 == 0 {
            let minutes = sharedCooldown / 60
            return minutes == 1 ? "1 min" : "\(minutes) min"
        }
        return "\(sharedCooldown)s"
    }

    // MARK: - Metric sections

    private var metricSections: some View {
        ForEach(Self.metricOrder, id: \.self) { kind in
            metricSection(for: kind)
        }
    }

    private func metricSection(for kind: MetricKind) -> some View {
        let draft = draftBinding(kind)
        let isLocked = Self.proKinds.contains(kind) && !viewModel.isPro

        return Section {
            Toggle("Enabled", isOn: draft.isEnabled)
                .font(AppFont.body)
                .disabled(isLocked)

            Picker("Condition", selection: draft.op) {
                Text("Above").tag(MetricAlert.Operator.above)
                Text("Below").tag(MetricAlert.Operator.below)
            }
            .disabled(isLocked)

            thresholdControl(draft: draft, kind: kind)
                .disabled(isLocked)

            if isLocked {
                Label("Pro feature — upgrade to configure", systemImage: "lock.fill")
                    .font(AppFont.caption)
                    .foregroundColor(Color.textSecondary)
            }
        } header: {
            HStack(spacing: AppSpacing.xs) {
                Text(metricTitle(for: kind))
                    .font(AppFont.body)
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(AppFont.caption)
                        .foregroundColor(Color.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func thresholdControl(draft: Binding<MetricDraft>, kind: MetricKind) -> some View {
        if kind == .network {
            HStack {
                Text("Threshold")
                    .font(AppFont.body)
                Spacer()
                Text(networkThresholdLabel(draft.wrappedValue.threshold))
                    .font(AppFont.callout)
                    .foregroundColor(Color.textSecondary)
            }
            Slider(value: draft.threshold, in: 0...100_000_000, step: 1_000_000)
            Text("0–100 MB/s")
                .font(AppFont.caption)
                .foregroundColor(Color.textSecondary)
        } else {
            HStack {
                Text("Threshold")
                    .font(AppFont.body)
                Spacer()
                Text("\(Int(draft.wrappedValue.threshold))\(unitLabel(for: kind))")
                    .font(AppFont.callout)
                    .foregroundColor(Color.textSecondary)
            }
            Slider(value: draft.threshold, in: thresholdRange(for: kind), step: 1)
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
                saveDrafts()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private func saveDrafts() {
        var enabled: [MetricAlert] = []
        for kind in Self.metricOrder {
            guard let draft = drafts[kind], draft.isEnabled else { continue }
            enabled.append(MetricAlert(
                id: draft.id,
                kind: draft.kind,
                op: draft.op,
                threshold: draft.threshold,
                isEnabled: true,
                cooldownSeconds: sharedCooldown,
                lastTriggeredAt: draft.lastTriggeredAt
            ))
        }
        viewModel.applyConfig(enabled)
    }

    // MARK: - Bindings

    private func draftBinding(_ kind: MetricKind) -> Binding<MetricDraft> {
        Binding(
            get: {
                drafts[kind] ?? MetricDraft(kind: kind, threshold: Self.defaultThreshold(for: kind))
            },
            set: { drafts[kind] = $0 }
        )
    }

    // MARK: - Helpers

    private func thresholdRange(for kind: MetricKind) -> ClosedRange<Double> {
        switch kind {
        case .temperature: return 0...100
        case .fan: return 0...10_000
        default: return 0...100 // cpu, memory, disk, battery — percent
        }
    }

    private func networkThresholdLabel(_ value: Double) -> String {
        String(format: "%.0f MB/s", value / 1_000_000)
    }

    private func metricTitle(for kind: MetricKind) -> String {
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

    nonisolated fileprivate static func defaultThreshold(for kind: MetricKind) -> Double {
        switch kind {
        case .cpu, .memory: return 80
        case .disk: return 90
        case .network: return 10_000_000
        case .temperature: return 80
        case .fan: return 3_000
        case .battery: return 80
        }
    }

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

/// Mutable per-metric editor state.  Mirrors `MetricAlert` with `var`
/// properties so SwiftUI bindings can mutate it in place.
private struct MetricDraft: Equatable {
    var id: UUID
    var kind: MetricKind
    var isEnabled: Bool
    var op: MetricAlert.Operator
    var threshold: Double
    var cooldownSeconds: Int
    var lastTriggeredAt: Date?

    init(
        id: UUID = UUID(),
        kind: MetricKind,
        isEnabled: Bool = false,
        op: MetricAlert.Operator = .above,
        threshold: Double,
        cooldownSeconds: Int = AlertEditorView.cooldownDefault,
        lastTriggeredAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.isEnabled = isEnabled
        self.op = op
        self.threshold = threshold
        self.cooldownSeconds = cooldownSeconds
        self.lastTriggeredAt = lastTriggeredAt
    }

    /// Seed a draft from an existing persisted alert, or fall back to a
    /// sensible default (disabled) for metrics without an alert.
    init(existing: MetricAlert?, kind: MetricKind) {
        if let existing {
            self.init(
                id: existing.id,
                kind: existing.kind,
                isEnabled: existing.isEnabled,
                op: existing.op,
                threshold: existing.threshold,
                cooldownSeconds: existing.cooldownSeconds,
                lastTriggeredAt: existing.lastTriggeredAt
            )
        } else {
            self.init(kind: kind, threshold: AlertEditorView.defaultThreshold(for: kind))
        }
    }
}
