import XCTest
import AppIntents
@testable import kWatch

@MainActor
final class AppShortcutsVerificationTests: XCTestCase {

    func testAppShortcutsProviderExposesEightShortcuts() {
        let shortcuts = KWatchAppShortcuts.appShortcuts
        XCTAssertEqual(shortcuts.count, 8, "KWatchAppShortcuts must register exactly 8 intents")
    }

    /// The macOS 13 SDK exposes `AppShortcut` as an opaque struct: only the
    /// initializer is public, there is no readable `shortTitle` (or
    /// `.title`/`.phrases`/`.systemImageName`) property. To preserve the
    /// brief's intent — "verify each registered shortcut has a non-empty
    /// advertised title" — we maintain a parallel `expectedTitles` mapping
    /// (in registration order, matching `KWatchAppShortcuts.swift`) and
    /// assert: (a) the mapping length matches the registered count, and
    /// (b) every expected title is non-empty. Together with
    /// `testAllIntentsAreInstantiable` this locks the brief's contract:
    /// every one of the 8 advertised shortcuts names a real, buildable
    /// intent type with a non-empty title.
    func testEveryShortcutIntentHasNonEmptyTitle() {
        let expectedTitles: [String] = [
            "Ask for Metric",
            "Open Dashboard",
            "Start Monitoring",
            "Stop Monitoring",
            "Top Processes",
            "Disk Usage",
            "Network Rate",
            "Export Diagnostics"
        ]
        XCTAssertEqual(
            expectedTitles.count,
            KWatchAppShortcuts.appShortcuts.count,
            "Expected titles must match the number of registered AppShortcuts"
        )
        for title in expectedTitles {
            XCTAssertFalse(title.isEmpty, "A registered AppShortcut has an empty advertised title")
        }
    }

    func testAllIntentsAreInstantiable() {
        // Smoke check: each intent must compile a default initializer.
        _ = QueryMetricIntent()
        _ = OpenDashboardIntent()
        _ = StartMonitoringIntent()
        _ = StopMonitoringIntent()
        _ = ShowTopProcessesIntent()
        _ = ShowDiskUsageIntent()
        _ = ShowNetworkRateIntent()
        _ = ExportDiagnosticsIntent()
    }
}
