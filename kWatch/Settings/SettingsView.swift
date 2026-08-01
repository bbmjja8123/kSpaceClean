import SwiftUI
import MetricsKit
import DesignSystem

/// Container view for the Settings window. Renders a tabbed sidebar with
/// four panes: Menu Bar, Notifications, General, and About. Each pane is
/// a small dedicated view that owns its own sub-state but reads/writes
/// through `SettingsViewModel` so changes are persisted immediately.
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
                    Label("Menu Bar", systemImage: "menubar.rectangle")
                }
                .tag(SettingsTab.menuBar)

            AlertSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Alerts", systemImage: "bell.badge")
                }
                .tag(SettingsTab.alerts)

            WidgetSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            AboutView(viewModel: viewModel, onCloseRequested: onCloseRequested)
                .tabItem {
                    Label("About", systemImage: "info.circle")
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
            Button("OK", role: .cancel) { viewModel.clearError() }
        } message: { message in
            Text(message)
        }
    }

    /// Tabs surfaced by the Settings window. Stable raw values are used so
    /// the persisted selection survives rebuilds.
    public enum SettingsTab: Hashable {
        case menuBar
        case alerts
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
                Text("Notifications")
            } footer: {
                Text("Allow kWatch to deliver alerts when a metric crosses your thresholds.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Section {
                Button(role: .destructive) {
                    viewModel.resetOnboarding()
                } label: {
                    Label("Show Onboarding Again", systemImage: "arrow.uturn.left")
                }
            } header: {
                Text("Onboarding")
            } footer: {
                Text("kWatch will display the welcome flow the next time you launch the app.")
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
                Text("System Permission")
                    .font(.headline)
                Text(viewModel.isNotificationsAuthorized ? "Authorized" : "Not Authorized")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            if viewModel.isNotificationsAuthorized {
                Button("Open System Settings…") {
                    viewModel.openNotificationSystemSettings()
                }
                .controlSize(.small)
            } else {
                Button("Enable Notifications") {
                    Task { await viewModel.requestNotificationPermission() }
                }
                .controlSize(.small)
            }
        }
    }
}

// MARK: - General / sampling pane

/// Sampling interval slider and launch-at-login toggle. macOS 13+ already
/// supports `SMAppService` for login items so we keep the preference as the
/// source of truth and let `LaunchAtLoginManager` reconcile on launch.
struct WidgetSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                samplingRow
            } header: {
                Text("Sampling")
            } footer: {
                Text("Higher rates consume more CPU and battery. The default 2s is a good balance.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Section {
                Toggle(isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                            .font(.headline)
                        Text("Start kWatch automatically when you sign in.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text("Startup")
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }

    private var samplingRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Interval")
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
}