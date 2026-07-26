import SwiftUI
import MetricsKit

/// Displays the list of threshold alerts with enable/disable toggles,
/// add and delete actions, and a notification-permission banner.
struct AlertsView: View {
    @StateObject private var viewModel: AlertsViewModel

    init(viewModel: AlertsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if !viewModel.isNotificationsAuthorized {
                notificationPermissionBanner
            }

            if viewModel.alerts.isEmpty {
                emptyState
            } else {
                alertList
            }
        }
        .onAppear {
            viewModel.refresh()
            viewModel.ensureDefaults()
        }
        .sheet(isPresented: $viewModel.isPresentingEditor) {
            if let alert = viewModel.editingAlert {
                AlertEditorView(viewModel: viewModel, alert: alert)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Alerts")
                .font(.title)
            Spacer()
            Button(action: viewModel.beginAdd) {
                Label("Add", systemImage: "plus")
            }
        }
        .padding()
    }

    // MARK: - Notification permission banner

    private var notificationPermissionBanner: some View {
        HStack {
            Text("Enable notifications to receive alert.")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("Enable") {
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
                .foregroundColor(.secondary)
            Text("No Alerts")
                .font(.headline)
            Text("Tap Add to create a threshold alert.")
                .font(.caption)
                .foregroundColor(.secondary)
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
                    .foregroundColor(.secondary)
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
        case .temperature:
            unit = "°C"
        case .fan:
            unit = " RPM"
        }
        return "\(opSymbol) \(Int(alert.threshold))\(unit)  ·  cooldown \(alert.cooldownSeconds)s"
    }
}
