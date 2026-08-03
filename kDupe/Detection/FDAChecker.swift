//
//  FDAChecker.swift
//  kSift
//
//  Detects whether the app currently holds Full Disk Access and deep-links
//  to the matching System Settings pane. Used by the onboarding permission
//  card and the scan guard so users never scan with an incomplete view.
//

import AppKit
import Foundation

/// Whether kSift currently holds Full Disk Access.
public enum FDAStatus: Equatable, Sendable {
    /// No probe has run yet.
    case unknown
    /// Full Disk Access is granted; protected folders are readable.
    case granted
    /// Full Disk Access is not granted; scans will miss protected folders.
    case denied
}

/// Read-only probe for the Full Disk Access permission.
///
/// macOS keeps Desktop, Documents, Downloads and most of `~/Library` behind
/// the Full Disk Access TCC control. A sandboxed app cannot read those paths
/// until the user grants the permission, so probing a TCC-gated path is a
/// reliable passive signal. This type never prompts; opening System Settings
/// is left to ``openSystemSettings()``, which the UI calls on user action.
public struct FDAChecker {
    /// Paths macOS keeps behind the Full Disk Access control. Any readable
    /// entry is treated as proof of access, so a path being absent on an
    /// unusual system does not produce a false negative.
    private static let protectedPaths: [String] = {
        let home = NSHomeDirectory()
        return [
            "\(home)/Library/Safari/Bookmarks.plist",
            "\(home)/Library/Mail",
            "\(home)/Library/Application Support/com.apple.TCC"
        ]
    }()

    /// Probes Full Disk Access and returns the current status.
    ///
    /// The check is cheap and safe to run on every scan attempt — the user
    /// can grant or revoke the permission while the app is running.
    public static func status() -> FDAStatus {
        for path in protectedPaths where FileManager.default.isReadableFile(atPath: path) {
            return .granted
        }
        return .denied
    }

    /// Deep-links to System Settings → Privacy & Security → Full Disk Access.
    public static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}
