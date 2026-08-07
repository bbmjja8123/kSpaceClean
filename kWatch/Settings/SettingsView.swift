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
                    Label(String(localized: "Alerts"), systemImage: "bell.badge")
                }
                .tag(SettingsTab.alerts)

            MetricSettingsView(viewModel: viewModel)
                .tabItem {
                    Label(String(localized: "Metrics"), systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(SettingsTab.metrics)

            AppearanceSettingsView(viewModel: viewModel)
                .tabItem {
                    Label(String(localized: "Appearance"), systemImage: "paintbrush")
                }
                .tag(SettingsTab.appearance)

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
        .frame(width: 560, height: 420)
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
    /// the persisted selection survives rebuilds.
    public enum SettingsTab: Hashable {
        case menuBar
        case alerts
        case metrics
        case appearance
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
                Text(String(localized: "Allow kWatch to deliver alerts when a metric crosses your thresholds."))
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
                Text(String(localized: "kWatch will display the welcome flow the next time you launch the app."))
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
                        Text(String(localized: "Start kWatch automatically when you sign in."))
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
