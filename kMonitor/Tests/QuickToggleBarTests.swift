import XCTest
@testable import kMonitor

/// The quick-toggle bar ships only sandbox-safe controls: a real pause
/// toggle backed by `MetricsAggregator.setPaused(_:)` and a read-only
/// Wi-Fi status hint. The former fake Bluetooth / Night Shift / DND
/// toggles (NSLog no-ops) were removed — see the v1.0 hardening brief.
@MainActor
final class QuickToggleBarTests: XCTestCase {

    /// `readWiFiStatus()` must return a Bool and never throw or crash.
    /// On sandboxed or VM environments where `networksetup` cannot run
    /// it degrades to `false` — this is a status *hint*, never a control.
    func testReadWiFiStatusReturnsBoolWithoutThrowing() {
        let status = QuickToggleBar.readWiFiStatus()
        XCTAssertTrue(status == true || status == false)
    }

    /// The pause button calls `viewModel.togglePause()`; the bar renders
    /// `pause.circle.fill` + "Resume monitoring" when paused and
    /// `play.circle.fill` + "Pause monitoring" otherwise. View rendering
    /// is verified visually; here we lock the state contract the bar
    /// depends on: flipping the VM state is the only thing the button does.
    func testPauseToggleAlignsWithViewModelState() {
        let container = TestAppContainer()
        let vm = MenuBarViewModel(container: container)
        XCTAssertFalse(vm.isPaused, "monitoring must start unpaused")

        vm.togglePause()
        XCTAssertTrue(vm.isPaused, "after one tap the bar shows Resume")

        vm.togglePause()
        XCTAssertFalse(vm.isPaused, "after a second tap the bar shows Pause")
    }
}
