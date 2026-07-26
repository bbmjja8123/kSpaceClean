import SwiftUI

@main
struct kWatchApp: App {
    @NSApplicationDelegateAdaptor(kWatchAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("kWatch", systemImage: "gauge.with.dots.needle.bottom.50percent") {
            MenuBarRootView()
                .environmentObject(appDelegate.container.appState)
                .environmentObject(appDelegate.container.purchaseState)
        }
        .menuBarExtraStyle(.window)

        Window("kWatch Dashboard", id: "dashboard") {
            DashboardWindow()
                .environmentObject(appDelegate.container.appState)
                .environmentObject(appDelegate.container.purchaseState)
        }
        .defaultSize(width: 720, height: 480)
    }
}

private struct MenuBarRootView: View {
    var body: some View {
        Text("kWatch")
            .padding()
    }
}

private struct DashboardWindow: View {
    var body: some View {
        Text("Dashboard")
            .padding()
    }
}
