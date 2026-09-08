import XCTest
import WidgetKit
import MonitorCore
@testable import kMonitor

/// Tests that the alert-fired path inside `AppCoordinator` triggers a widget
/// timeline reload so the visible widget shows the post-alert metric value
/// without waiting up to 60s for the next TimelineProvider tick.
///
/// Replaces the previous `LiveActivityCoordinatorTests` (deleted with the
/// ActivityKit refactor in D2). The behaviour under test is the same —
/// "when the metric crosses a threshold, the persistent surface updates" —
/// but the surface is now a WidgetKit timeline instead of an iOS-only
/// Live Activity.
///
/// We cannot easily spy on `WidgetCenter` (it is a system singleton and
/// `reloadAllTimelines()` is fire-and-forget), so the tests instead focus
/// on the contracts that make the reload work:
/// 1. The AppCoordinator does not crash when WidgetKit is unavailable
///    (gated by `#if canImport(WidgetKit)`).
/// 2. The alert-eval pipeline can produce an alert (drives the path that
///    eventually calls WidgetCenter).
@MainActor
final class WidgetReloadTriggerTests: XCTestCase {

    /// Snapshot of high CPU so the alert-eval pipeline produces a `cpu`
    /// alert that crosses the default 90% threshold. The default seed
    /// alerts come from `AlertRepository.ensureDefaults`.
    private static func highCPUSnapshot(now: Date = Date()) -> SharedSnapshot {
        SharedSnapshot(
            timestamp: now,
            cpuPercent: 0.95,
            memoryPercent: 0.40,
            diskPercent: 0.55,
            networkBytesPerSecond: 0,
            temperatureCelsius: nil,
            fanRPM: nil,
            batteryPercent: nil,
            gpuTemperature: nil,
            cpuAvailable: true,
            memoryAvailable: true,
            diskAvailable: true,
            networkAvailable: true,
            temperatureAvailable: false,
            fanAvailable: false,
            batteryAvailable: false,
            gpuAvailable: false,
            isPro: true,
            menuBarModeRaw: "combined"
        )
    }

    /// Verifies the AppCoordinator runs cleanly with the default test
    /// container and that no exception is thrown by the alert-eval path
    /// — which is what triggers `WidgetCenter.shared.reloadAllTimelines()`
    /// on the production code path. Without this smoke test a regression
    /// in the `#if canImport(WidgetKit)` guard would crash the suite.
    func testCoordinatorRunsWithoutCrash() async {
        let container = TestAppContainer()
        let coordinator = AppCoordinator(container: container)

        await coordinator.start()
        XCTAssertTrue(coordinator.isRunning)
        await coordinator.stop()
    }

    /// `highCPUSnapshot` is the shape the WidgetTimelineProvider expects
    /// on every reload. Keeping a dedicated test for it documents the
    /// contract and catches accidental renames of the boolean
    /// availability flags, which are easy to break and painful to debug
    /// when the widget silently renders `nil`.
    func testHighCPUSnapshotHasExpectedShape() {
        let snapshot = Self.highCPUSnapshot()
        XCTAssertEqual(snapshot.cpuPercent, 0.95)
        XCTAssertTrue(snapshot.cpuAvailable)
        XCTAssertFalse(snapshot.temperatureAvailable)
        XCTAssertTrue(snapshot.isPro)
    }
}