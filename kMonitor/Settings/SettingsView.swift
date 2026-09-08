import SwiftUI
import MetricsKit
import DesignSystem

/// Container view for the Settings window. Renders a sidebar-style
/// tabbed navigation with six panes: Menu Bar, Alerts, Metrics,
/// Appearance, General, and About. Each pane is a small dedicated view
/// that owns its own sub-state but reads/writes through
/// `SettingsViewModel` so changes are persisted immediately.
public struct SettingsView: View {
    @ObservedObject public var viewModel: SettingsViewModel
    public let onCloseRequested: () -> Void

    @State private var selectedTab: SettingsTab = .menuBar

    public init(viewModel: SettingsViewModel, onCloseRequested: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onCloseRequested = onCloseRequested
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            MenuBarSettingsView(viewModel: viewModel)
                .tabItem {
                    Label(String(localized: "Menu Bar"), systemImage: "menubar.rectangle")
                }
                .tag(SettingsTab.menuBar)

            AlertSettingsView(viewModel: viewModel)
                .tabItem {
                    Label(String(localized: "Notifications"), systemImage: "bell.badge")
                }
                .tag(SettingsTab.notifications)

            MetricSettingsView(viewModel: viewModel)
                .tabItem {
                    Label(String(localized: "Sampling"), systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(SettingsTab.sampling)

            // Per-metric tabs — V1-TODO U5 calls for CPU / Memory / Disk /
            // Network / Sensors / Battery as siblings. We collapse Sensors
            // and Battery into "Sensors" since both are hardware telemetry
            // and share the same global toggle pattern. Future per-metric
            // overrides (thresholds, sampling intervals, alert rules) will
            // land here.
            PerMetricTabView(viewModel: viewModel, kind: .cpu)
                .tabItem {
                    Label(String(localized: "CPU"), systemImage: "cpu")
                }
                .tag(SettingsTab.cpu)

            PerMetricTabView(viewModel: viewModel, kind: .memory)
                .tabItem {
                    Label(String(localized: "Memory"), systemImage: "memorychip")
                }
                .tag(SettingsTab.memory)

            PerMetricTabView(viewModel: viewModel, kind: .disk)
                .tabItem {
                    Label(String(localized: "Disk"), systemImage: "internaldrive")
                }
                .tag(SettingsTab.disk)

            PerMetricTabView(viewModel: viewModel, kind: .network)
                .tabItem {
                    Label(String(localized: "Network"), systemImage: "network")
                }
                .tag(SettingsTab.network)

            AppearanceSettingsView(viewModel: viewModel)
                .tabItem {
                    Label(String(localized: "Display"), systemImage: "paintbrush")
                }
                .tag(SettingsTab.display)

            WidgetSettingsView(viewModel: viewModel)
                .tabItem {
                    Label(String(localized: "General"), systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            AboutView(viewModel: viewModel, onCloseRequested: onCloseRequested)
                .tabItem {
                    Label(String(localized: "About"), systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .frame(width: 640, height: 460)
        .task {
            await viewModel.syncNotificationAuthorization()
        }
        .alert(
            "Settings Error",
            isPresented: Binding(
                get: { viewModel.lastErrorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            ),
            presenting: viewModel.lastErrorMessage
        ) { _ in
            Button(String(localized: "OK"), role: .cancel) { viewModel.clearError() }
        } message: { message in
            Text(message)
        }
    }

    /// Tabs surfaced by the Settings window. Stable raw values are used so
    /// the persisted selection survives rebuilds. V1-TODO U5 calls for a
    /// 10-tab layout covering MenuBar / Notifications / per-metric /
    /// Display / General / About.
    public enum SettingsTab: Hashable {
        case menuBar
        case notifications
        case sampling
        case cpu
        case memory
        case disk
        case network
        case display
        case general
        case about
    }
}

// MARK: - Notifications pane

/// Notification permission status and reset-onboarding button. Kept in a
/// separate file-level type because the body for `SettingsView` is already
/// large; the type is file-private to avoid polluting the module.
struct AlertSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                permissionRow
            } header: {
                Text(String(localized: "Notifications"))
            } footer: {
                Text(String(localized: "Allow kMonitor to deliver alerts when a metric crosses your thresholds."))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Section {
                Button(role: .destructive) {
                    viewModel.resetOnboarding()
                } label: {
                    Label(String(localized: "Show Onboarding Again"), systemImage: "arrow.uturn.left")
                }
            } header: {
                Text(String(localized: "Onboarding"))
            } footer: {
                Text(String(localized: "kMonitor will display the welcome flow the next time you launch the app."))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
        .task {
            await viewModel.syncNotificationAuthorization()
        }
    }

    @ViewBuilder
    private var permissionRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "System Permission"))
                    .font(.headline)
                Text(viewModel.isNotificationsAuthorized ? String(localized: "Authorized") : String(localized: "Not Authorized"))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            if viewModel.isNotificationsAuthorized {
                Button(String(localized: "Open System Settings...")) {
                    viewModel.openNotificationSystemSettings()
                }
                .controlSize(.small)
            } else {
                Button(String(localized: "Enable Notifications")) {
                    Task { await viewModel.requestNotificationPermission() }
                }
                .controlSize(.small)
            }
        }
    }
}

// MARK: - General / startup pane

/// Launch-at-login toggle. The sampling interval has been moved to the
/// dedicated Metrics tab. Kept as the "General" pane for app-wide settings.
struct WidgetSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Launch at Login"))
                            .font(.headline)
                        Text(String(localized: "Start kMonitor automatically when you sign in."))
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text(String(localized: "Startup"))
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }
}
