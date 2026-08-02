import AppKit

/// Bridges AppKit UI (status items) to SwiftUI scene navigation.
@MainActor
public enum AppWindowRouter {
    /// Captured from a SwiftUI scene's `openWindow` environment action.
    public static var openDashboard: ((String) -> Void)?

    /// Opens the dashboard, preferring the captured `openWindow` action and
    /// falling back to activating the window by title.
    public static func openDashboardWindow() {
        if let openDashboard {
            openDashboard("dashboard")
            return
        }
        if let window = NSApp.windows.first(where: { $0.title == "kWatch Dashboard" }) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
