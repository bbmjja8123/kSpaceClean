import Foundation
import AppIntents

/// Surfaces kWatch's eight intents to Spotlight and the Shortcuts app.
///
/// `AppShortcutsProvider` is a singleton — the system instantiates it once and
/// indexes the returned `AppShortcuts` array for Spotlight search, the Shortcuts
/// gallery, and Siri suggestions. Invocation phrases appear in
/// `Localizable.xcstrings` so they ship in every supported language.
///
/// Free intents appear unconditionally. Pro intents are still indexed (so users
/// can discover them) but the dialog copy tells free users to upgrade.
@available(macOS 13.0, *)
public struct KWatchAppShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QueryMetricIntent(),
            phrases: [
                "Ask \(.applicationName) for \(\.$metric)"
            ],
            shortTitle: "Ask for Metric",
            systemImageName: "gauge.with.dots.needle.bottom.50percent"
        )

        AppShortcut(
            intent: OpenDashboardIntent(),
            phrases: [
                "Open \(.applicationName) dashboard"
            ],
            shortTitle: "Open Dashboard",
            systemImageName: "macwindow"
        )

        AppShortcut(
            intent: StartMonitoringIntent(),
            phrases: [
                "Start \(.applicationName) monitoring"
            ],
            shortTitle: "Start Monitoring",
            systemImageName: "play.circle"
        )

        AppShortcut(
            intent: StopMonitoringIntent(),
            phrases: [
                "Stop \(.applicationName) monitoring"
            ],
            shortTitle: "Stop Monitoring",
            systemImageName: "stop.circle"
        )

        AppShortcut(
            intent: ShowTopProcessesIntent(),
            phrases: [
                "Show top processes in \(.applicationName)"
            ],
            shortTitle: "Top Processes",
            systemImageName: "list.bullet.rectangle"
        )

        AppShortcut(
            intent: ShowDiskUsageIntent(),
            phrases: [
                "Show disk usage with \(.applicationName)"
            ],
            shortTitle: "Disk Usage",
            systemImageName: "internaldrive"
        )

        AppShortcut(
            intent: ShowNetworkRateIntent(),
            phrases: [
                "Show network rate with \(.applicationName)"
            ],
            shortTitle: "Network Rate",
            systemImageName: "network"
        )

        AppShortcut(
            intent: ExportDiagnosticsIntent(),
            phrases: [
                "Export \(.applicationName) diagnostics"
            ],
            shortTitle: "Export Diagnostics",
            systemImageName: "square.and.arrow.up"
        )
    }
}

// MARK: - Manual integration steps
//
// The developer must complete these Xcode steps before the intents extension
// builds. They are intentionally not automated by `project.yml`:
//
// 1. Add a new App Intents Extension target to the kWatch Xcode project:
//    File > New > Target > App Intents Extension.
// 2. Set Bundle ID to `app.kraftly.kwatch.intents`.
// 3. Set deployment target to macOS 13.
// 4. Add the eight intent Swift files plus this file to the new target.
// 5. Ensure the main app target also imports each intent type (it does so
//    transitively via `KWatchAppShortcuts`).
// 6. Add `NSUserActivityTypes` entries to the main app's Info.plist if you
//    adopt `NSUserActivity`-based shortcut suggestions.
// 7. Call `KWatchSpotlightIndexer.reindex()` from `kWatchApp.init()` (or after
//    onboarding completes) so Spotlight picks up the items.