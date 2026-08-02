import XCTest
import AppIntents
@testable import kWatch

@available(macOS 14.0, *)
@MainActor
final class InteractiveWidgetIntentTests: XCTestCase {

    func testOpenDashboardIntentIsInstantiable() {
        let intent = OpenDashboardIntent()
        XCTAssertNotNil(intent)
    }

    func testPauseMonitoringIntentIsInstantiable() {
        let intent = PauseMonitoringIntent()
        XCTAssertNotNil(intent)
    }

    func testPauseMonitoringIntentHasLocalizedTitle() {
        // Title should be present and non-empty so the widget button label
        // renders something useful (not a system fallback).
        let title = PauseMonitoringIntent.title
        let resolved = String(localized: title)
        XCTAssertFalse(resolved.isEmpty)
    }

    func testPauseMonitoringIntentUsesLockDialogForFreeUsers() async throws {
        // Inject a free-tier service; the intent must surface the locked-
        // dialog copy instead of stopping monitoring.
        let stub = StubIntentService(isPro: false)
        let intent = PauseMonitoringIntent(service: stub)
        _ = try await intent.perform()
        // Verify the service was never asked to stop — locked-dialog path
        // bails before the side effect.
        XCTAssertEqual(stub.stopCalls.current, 0)
    }
}