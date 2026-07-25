import AppKit
import Foundation

/// Manages the kDupe menu bar item with quick scan and app launch actions.
///
/// This class creates an `NSStatusItem` in the system menu bar, providing
/// one-click access to common kDupe operations such as quick scanning,
/// opening the main app window, and quitting the application.
@MainActor
public final class MenuBarManager: ObservableObject {
    private let statusItem: NSStatusItem

    /// The notification name posted when the user selects "Quick Scan".
    public static let quickScanNotificationName = Notification.Name("com.kraftly.kdupe.quickScan")

    /// Creates the menu bar item and its associated menu.
    public init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "kDupe")
            button.action = #selector(statusItemClicked)
            button.target = self
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        let quickScanItem = NSMenuItem(
            title: "Quick Scan",
            action: #selector(quickScan),
            keyEquivalent: "s"
        )
        quickScanItem.target = self
        menu.addItem(quickScanItem)

        let openItem = NSMenuItem(
            title: "Open kDupe",
            action: #selector(openApp),
            keyEquivalent: "o"
        )
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func statusItemClicked() {
        // The menu will display automatically when the status item is clicked;
        // this selector exists so the button has a target-action pair.
    }

    /// Posts a notification to trigger a quick scan from the main app.
    @objc private func quickScan() {
        NotificationCenter.default.post(name: Self.quickScanNotificationName, object: nil)
    }

    /// Opens the main kDupe application.
    @objc private func openApp() {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "app.kraftly.kdupe") else {
            return
        }
        NSWorkspace.shared.open(appURL)
    }

    /// Terminates the application.
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
