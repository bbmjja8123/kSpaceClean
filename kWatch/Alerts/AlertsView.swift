import SwiftUI
import MetricsKit
import DesignSystem

/// Displays the list of threshold alerts with enable/disable toggles,
/// add and delete actions, and a notification-permission banner.
struct AlertsView: View {
    @StateObject private var viewModel: AlertsViewModel
    private let onBack: () -> Void

    init(viewModel: AlertsViewModel, onBack: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onBack = onBack
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            content
        }
        .onAppear {
            viewModel.refresh()
            viewModel.ensureDefaults()
            Task { await viewModel.syncNotificationAuthorization() }
        }
        .sheet(isPresented: $viewModel.isPresentingEditor) {
            if let alert = viewModel.editingAlert {
                AlertEditorView(viewModel: viewModel, alert: alert)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Button(action: onBack) {
                Label(String(localized: "Back"), systemImage: "chevron.left")
            }
            .help(String(localized: "Back to dashboard"))

            Spacer()

            Text(String(localized: "Alerts"))
                .font(.headline)

            Spacer()

            Button(action: viewModel.beginAdd) {
                Label(String(localized: "Add"), systemImage: "plus")
            }
            .help(String(localized: "Add alert"))
        }
        .padding()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !viewModel.isNotificationsAuthorized {
            notificationPermissionBanner
        }

        if viewModel.alerts.isEmpty {
            emptyState
        } else {
            alertList
        }
    }

    // MARK: - Notification permission banner

    private var notificationPermissionBanner: some View {
        HStack {
            Text(String(localized: "Enable notifications to receive alert."))
                .font(.caption)
                .foregroundColor(Color.textSecondary)
            Spacer()
            Button(String(localized: "Enable")) {
                Task { await viewModel.requestNotificationPermission() }
            }
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.badge")
                .font(.largeTitle)
                .foregroundColor(Color.textSecondary)
            Text(String(localized: "No Alerts"))
                .font(.headline)
            Text(String(localized: "Tap Add to create a threshold alert."))
                .font(.caption)
                .foregroundColor(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Alert list

    private var alertList: some View {
        List {
            ForEach(viewModel.alerts) { alert in
                AlertRow(alert: alert, viewModel: viewModel)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.beginEdit(alert)
                    }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    viewModel.delete(viewModel.alerts[index])
                }
            }
        }
    }
}

// MARK: - Alert row

private struct AlertRow: View {
    let alert: MetricAlert
    @ObservedObject var viewModel: AlertsViewModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.kind.rawValue.capitalized)
                    .font(.headline)
                Text(conditionDescription)
                    .font(.caption)
                    .foregroundColor(Color.textSecondary)
            }
            Spacer()
            Toggle(isOn: Binding(
                get: { alert.isEnabled },
                set: { _ in viewModel.toggle(alert) }
            )) {
                EmptyView()
            }
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private var conditionDescription: String {
        let opSymbol = alert.op == .above ? ">" : "<"
        let unit: String
        switch alert.kind {
        case .cpu, .memory, .disk, .battery:
            unit = "%"
        case .network:
            unit = " B/s"
        case .temperature, .gpu:
            unit = "°C"
        case .fan:
            unit = " RPM"
        }
        return "\(opSymbol) \(Int(alert.threshold))\(unit)  ·  cooldown \(alert.cooldownSeconds)s"
    }
}
