import SwiftUI
import AppKit
import DesignSystem

/// A row of quick controls at the top of the menu-bar popover.
///
/// Everything here is genuinely functional inside the App Store sandbox:
/// - Pause monitoring: gates the `MetricsAggregator` sampling loop.
/// - Wi-Fi status: read-only indicator; tapping opens the system Wi-Fi
///   settings pane (writing network configuration is not sandbox-safe).
public struct QuickToggleBar: View {
    @ObservedObject public var viewModel: MenuBarViewModel
    var onOpenSystemSettings: (() -> Void)? = nil

    /// Lazily probed Wi-Fi hardware state — probed once per popover
    /// appearance so `networksetup` is never spawned on every render.
    @State private var wifiOn: Bool = false

    public init(viewModel: MenuBarViewModel, onOpenSystemSettings: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onOpenSystemSettings = onOpenSystemSettings
    }

    public var body: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.togglePause()
            } label: {
                icon(
                    viewModel.isPaused ? "pause.circle.fill" : "play.circle.fill",
                    active: !viewModel.isPaused
                )
            }
            .buttonStyle(.plain)
            .help(String(localized: viewModel.isPaused ? "Resume monitoring" : "Pause monitoring"))

            Button {
                (onOpenSystemSettings ?? Self.openWiFiSettings)()
            } label: {
                icon("wifi", active: wifiOn)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Wi-Fi status — click to open Network settings"))

            Spacer()
        }
        .padding(.vertical, 4)
        .onAppear {
            wifiOn = Self.readWiFiStatus()
        }
    }

    private func icon(_ name: String, active: Bool) -> some View {
        Image(systemName: name)
            .foregroundStyle(active ? Color.brandPrimary : Color.textSecondary)
    }

    /// Read-only Wi-Fi hardware status via `networksetup -getairportpower`.
    /// Returns `false` silently when the command is unavailable (sandbox
    /// or VMs without en0) — this is a status *hint*, never a control.
    public static func readWiFiStatus() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-getairportpower", "en0"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (String(data: data, encoding: .utf8) ?? "").contains("On")
        } catch {
            return false
        }
    }

    /// Deep-link into System Settings → Wi-Fi (public URL scheme).
    public static func openWiFiSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-duiextension") {
            NSWorkspace.shared.open(url)
        }
    }
}
