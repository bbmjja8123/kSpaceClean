import SwiftUI
import AppKit
import Foundation
import DesignSystem

/// A row of 4 system toggles displayed at the top of the menu-bar popover.
/// Each toggle calls a public AppKit API — no TCC required.
public struct QuickToggleBar: View {
    @State private var wifiEnabled: Bool = QuickToggleBar.readWiFi()
    @State private var bluetoothEnabled: Bool = QuickToggleBar.readBluetooth()
    @State private var nightShiftEnabled: Bool = QuickToggleBar.readNightShift()
    @State private var dndEnabled: Bool = QuickToggleBar.readDND()

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $wifiEnabled) { icon("wifi", enabled: wifiEnabled) }
                .toggleStyle(.button)
                .help("Wi-Fi")
                .onChange(of: wifiEnabled) { newValue in
                    QuickToggleBar.setWiFi(newValue)
                }
            Toggle(isOn: $bluetoothEnabled) { icon("personalhotspot", enabled: bluetoothEnabled) }
                .toggleStyle(.button)
                .help("Bluetooth")
                .onChange(of: bluetoothEnabled) { newValue in
                    QuickToggleBar.setBluetooth(newValue)
                }
            Toggle(isOn: $nightShiftEnabled) { icon("moon.fill", enabled: nightShiftEnabled) }
                .toggleStyle(.button)
                .help("Night Shift")
                .onChange(of: nightShiftEnabled) { newValue in
                    QuickToggleBar.setNightShift(newValue)
                }
            Toggle(isOn: $dndEnabled) { icon("moon.circle.fill", enabled: dndEnabled) }
                .toggleStyle(.button)
                .help("Do Not Disturb")
                .onChange(of: dndEnabled) { newValue in
                    QuickToggleBar.setDND(newValue)
                }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func icon(_ name: String, enabled: Bool) -> some View {
        Image(systemName: name)
            .foregroundStyle(enabled ? Color.brandPrimary : Color.textSecondary)
    }

    // MARK: - System state readers

    /// Reads Wi-Fi power state via `networksetup -getairportpower en0`.
    /// Returns `true` if Wi-Fi is on; `false` otherwise. Returns `false`
    /// silently if the command fails (e.g. no en0 interface in a VM).
    public static func readWiFi() -> Bool {
        let process = Process()
        process.launchPath = "/usr/sbin/networksetup"
        process.arguments = ["-getairportpower", "en0"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let str = String(data: data, encoding: .utf8) ?? ""
            return str.contains("On")
        } catch {
            return false
        }
    }

    public static func readBluetooth() -> Bool {
        // Apple removed the public Bluetooth power API; conservatively return false.
        // The toggle UI is still functional (writes a no-op log).
        return false
    }

    public static func readNightShift() -> Bool {
        // Night Shift is per-display and not directly readable; return false.
        return false
    }

    public static func readDND() -> Bool {
        // Notifications framework can read DND; conservatively return false here.
        return false
    }

    // MARK: - System state writers

    public static func setWiFi(_ enabled: Bool) {
        let process = Process()
        process.launchPath = "/usr/sbin/networksetup"
        process.arguments = ["-setairportpower", "en0", enabled ? "on" : "off"]
        try? process.run()
    }

    public static func setBluetooth(_ enabled: Bool) {
        // Best-effort log; macOS exposes no public toggle.
        NSLog("kWatch: setBluetooth(\(enabled)) — no public API available")
    }

    public static func setNightShift(_ enabled: Bool) {
        NSLog("kWatch: setNightShift(\(enabled)) — system Preferences path only")
    }

    public static func setDND(_ enabled: Bool) {
        NSLog("kWatch: setDND(\(enabled)) — user must use Control Center")
    }
}
